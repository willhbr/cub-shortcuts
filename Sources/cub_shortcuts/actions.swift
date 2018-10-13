import Foundation
import Cub

class Body {
  let superBod: Body?
  var statements = [Expression]()
  var functions = [String: Function]()
  private var functionsToCheck = Set<String>()

  init(parent: Body? = nil) {
    superBod = parent
  }

  var isGlobal: Bool { return superBod == nil }
  var lastUUID: String { return statements.last!.uuid }

  func addExpression(_ expression: Expression) {
    statements.append(expression)
  }

  func ensureDefined(function: String) {
    if let _ = functions[function] {
      return
    } else {
      functionsToCheck.insert(function)
    }
  }

  func registerFunction(_ function: Function) {
    self.functions[function.name] = function
  }

  func encode() -> NSDictionary {
    return [
      "WFWorkflowActions": functions["main"]!.body.statements.map { $0.encode() }
    ]
  }
}

struct Expression {
  let id: String
  let params: [String: Any]
  let uuid: String
  let conditionalGroup: String?

  init(id: String, params: [String: Any], group: String? = nil) {
    self.id = id
    self.params = params
    self.conditionalGroup = group
    self.uuid = UUID().uuidString
  }

  func encode() -> NSDictionary {
    var dict = params
    if let group = conditionalGroup, id.hasSuffix("conditional") {
      dict["GroupingIdentifier"] = group
    }
    dict["UUID"] = uuid
    return [
      "WFWorkflowActionIdentifier": id,
      "WFWorkflowActionParameters": dict,
    ]
  }
}

protocol ShortcutGeneratable {
  func generate(body: Body) throws
}

func gen(_ node: ASTNode, _ body: Body) throws {
  if body.isGlobal {
    guard let _ = node as? FunctionNode else {
      throw parseError(node, "Can only have functions at top level")
    }
  }
  switch node {
  case let generatable as ShortcutGeneratable:
    try generatable.generate(body: body)
  default:
    throw parseError(node, "Can't generate \(node)")
  }
}

extension AssignmentNode: ShortcutGeneratable {
  func generate(body: Body) throws {
    try gen(self.value, body)
    switch self.variable {
    case let iden as VariableNode:
      body.addExpression(Expression(id: "is.workflow.actions.setvariable",
        params: ["WFVariableName": iden.name]))
    default:
      throw parseError(self, "Can't assign to \(self.variable)")
    }
  }
}

extension VariableNode: ShortcutGeneratable {
  func generate(body: Body) throws {
    body.addExpression(
      Expression(id: "is.workflow.actions.getvariable",
                 params: [
                   "WFVariable": [
                     "Value": [
                       "Type": "Variable",
                       "VariableName": name],
                   // Does this depend on the type?
                   "WFSerializationType": "WFTextTokenAttachment"]]))
  }
}

extension NumberNode: ShortcutGeneratable {
  func generate(body: Body) throws {
    body.addExpression(Expression(id: "is.workflow.actions.number",
                                  params: ["WFNumberActionNumber": value]))
  }
}

extension StringNode: ShortcutGeneratable {
  func generate(body: Body) throws {
    body.addExpression(Expression(id: "is.workflow.actions.gettext",
                                  params: ["WFTextActionText": value]))
  }
}

extension ArrayNode: ShortcutGeneratable {
  func generate(body: Body) throws {
    let tmpName = UUID().uuidString
    body.addExpression(Expression(id: "is.workflow.actions.list",
                          params: ["WFItems": [Any]()]))
    body.addExpression(Expression(id: "is.workflow.actions.setvariable",
        params: ["WFVariableName": tmpName]))

    for value in self.values {
      try gen(value, body)
      body.addExpression(Expression(id: "is.workflow.actions.appendvariable",
                                    params: ["WFVariableName": tmpName]))
    }
    body.addExpression(
      Expression(id: "is.workflow.actions.getvariable",
                 params: [
                   "WFVariable": [
                     "Value": [
                       "Type": "Variable",
                       "VariableName": tmpName],
                   // Does this depend on the type?
                   "WFSerializationType": "WFTextTokenAttachment"]]))
  }
}

extension ArraySubscriptNode: ShortcutGeneratable {
  func generate(body: Body) throws {
    try gen(variable, body)
    try gen(name, body)
  }
}

func numberFrom(uuid: String) -> [String: Any] {
  return ["Value": [
    // Not sure if this is necessary
    "OutputName": "Number",
    "OutputUUID": uuid,
    "Type": "ActionOutput"
  ], "WFSerializationType": "WFTextTokenAttachment"]
}

func stringFrom(uuid: String) -> [String: Any] {
  return ["Value": [
            "attachmentsByRange": [
              "{0, 1}": [
                "OutputName": "String",
                "OutputUUID": uuid,
                "Type": "ActionOutput"]],
              "string": "\u{fffc}",
  ],
  "WFSerializationType": "WFTextTokenString"] 
}

extension BinaryOpNode: ShortcutGeneratable {
  func generate(body: Body) throws {
    guard let rhs = self.rhs else {
      throw parseError(self, "Can't do unary operators, sorry")
    }
    try gen(rhs, body)
    let rhsUUID = body.lastUUID
    try gen(lhs, body)
    let lhsUUID = body.lastUUID
    let op: String
    switch opInstructionType {
    case .add: op = "+"
    case .sub: op = "-"
    case .mul: op = "\u{00d7}"
    case .div: op = "\u{00f7}"
    case .eq: 
      try generateNonMathOp(node: self, lhsUUID: lhsUUID, rhsUUID: rhsUUID, body)
      return
    default: throw parseError(self, "I don't support that operator yet")
    }
    body.addExpression(
      Expression(id: "is.workflow.actions.math",
                 params: [
                   "WFMathOperand": numberFrom(uuid: rhsUUID),
                   "WFMathOperation": op])
      )
  }
}

func generateNonMathOp(node: BinaryOpNode, lhsUUID: String, rhsUUID: String, _ body: Body) throws {
  switch node.opInstructionType {
    case .eq:
      try generateConditional(condition: "Equals", lhsUUID, rhsUUID, invert: false, body)
    default:
      throw parseError(node, "Cannot generate operation: \(node)")
  }
}

func generateConditional(condition: String, _ lhsUUID: String, _ rhsUUID: String,
                         invert: Bool, _ body: Body) throws {
  let group = UUID().uuidString
  let trueValue: String
  let falseValue: String
  if invert {
    trueValue = "FALSE"
    falseValue = "TRUE"
  } else {
    trueValue = "TRUE"
    falseValue = "FALSE"
  }
  body.addExpression(Expression(id: "is.workflow.actions.conditional",
                 params: ["WFControlFlowMode": 0, // I think 0 is 'start conditional'
                          "WFCondition": condition,
                          "WFConditionalActionString": stringFrom(uuid: rhsUUID)],
                          group: group))
  body.addExpression(Expression(id: "is.workflow.actions.gettext",
                                params: ["WFTextActionText": trueValue]))
  body.addExpression(Expression(id: "is.workflow.actions.conditional",
                 params: ["WFControlFlowMode": 1],
                 group: group)) // I think 1 is 'break between if/else'
  body.addExpression(Expression(id: "is.workflow.actions.gettext",
                                params: ["WFTextActionText": falseValue]))
  body.addExpression(Expression(id: "is.workflow.actions.conditional",
                 params: ["WFControlFlowMode": 2],
                 group: group)) // I think 2 is 'endif'
}

extension CallNode: ShortcutGeneratable {
  func generate(body: Body) throws {
    if !(try addBuiltinAction(node: self, args: arguments, body)) {
      body.ensureDefined(function: callee)
    }
  }
}

struct Function {
  let name: String
  let arguments: [String]
  let body: Body
}

extension FunctionNode: ShortcutGeneratable {
  func generate(body: Body) throws {
    if self.prototype.returns {
      throw parseError(self, "Cannot have returning functions yet")
    }
    let newBod = Body(parent: body)
    for statement in self.body.nodes {
      try gen(statement, newBod)
    }
    body.registerFunction(Function(name: prototype.name,
                                   arguments: prototype.argumentNames,
                                   body: newBod))
  }
}

extension ReturnNode: ShortcutGeneratable {
  func generate(body: Body) throws {
    if let value = self.value {
      try gen(value, body)
    }
    // TODO generate a return thingy here
  }
}

struct ParseError: Error {
  let message: String
  let location: Range<Int>?
}

func parseError(_ node: ASTNode, _ message: String) -> ParseError {
  return ParseError(message: message, location: node.range)
}
