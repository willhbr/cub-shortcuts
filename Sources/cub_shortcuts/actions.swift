import Foundation
import Cub

class Program {
  var workflowName: String? = nil
  var functions = [String: Function]()
  private var functionsToCheck = Set<String>()

  func ensureDefined(function: String) {
    if let _ = functions[function] {
      return
    } else {
      functionsToCheck.insert(function)
    }
  }

  func checkFunctions() throws {
    for function in functionsToCheck {
      if functions[function] == nil {
        throw ParseError(message: "Function '\(function)' not defined.", location: nil)
      }
    }
  }

  func getWorkflowName() throws -> String {
    if let name = workflowName {
      return name
    }
    fatalError("Must define workflow name at top of file: workflow(...)")
  }
}

class Body {
  let superBod: Body?
  var statements = [Expression]()
  let program: Program

  init(parent: Body? = nil) {
    superBod = parent
    if let parent = parent {
      program = parent.program
    } else {
      program = Program()
    }
  }

  var isGlobal: Bool { return superBod == nil }
  var lastUUID: String { return statements.last!.uuid }

  func addExpression(_ expression: Expression) {
    statements.append(expression)
  }

  func ensureDefined(function: String) {
    program.ensureDefined(function: function)
  }

  func registerFunction(_ function: Function) {
    program.functions[function.name] = function
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
    if let group = conditionalGroup {
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
  if let _ = node as? CommentNode {
    return
  }
  if body.isGlobal {
    if let call = node as? CallNode {
      if call.callee != "workflow" {
        throw parseError(node, "Only functions and workflow name allowed at top level")
      }
      if let name = call.arguments.first as? StringNode,
          call.arguments.count == 1 {
        body.program.workflowName = name.value
        return
      }
      throw parseError(node,
                       "Workflow name must be defined with string literal: workflow(\"My Workflow\")")
    }
    guard let _ = node as? FunctionNode else {
      throw parseError(node, "Only functions and workflow name allowed at top level")
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

func dictFrom(uuid: String) -> [String: Any] {
  return ["Value": [
    // Not sure if this is necessary
    "OutputName": "Dictionary",
    "OutputUUID": uuid,
    "Type": "ActionOutput"
  ], "WFSerializationType": "WFTextTokenAttachment"]
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
    let op: String
    switch opInstructionType {
    case .add: op = "+"
    case .sub: op = "-"
    case .mul: op = "\u{00d7}"
    case .div: op = "\u{00f7}"
    default: 
      try generateNonMathOp(node: self, body)
      return
    }
    try gen(rhs, body)
    let rhsUUID = body.lastUUID
    try gen(lhs, body)
    body.addExpression(
      Expression(id: "is.workflow.actions.math",
                 params: [
                   "WFMathOperand": numberFrom(uuid: rhsUUID),
                   "WFMathOperation": op])
      )
  }
}

func generateNonMathOp(node: BinaryOpNode, _ body: Body) throws {
  let lhs = node.lhs
  let rhs = node.rhs!
  try gen(rhs, body)
  let rhsUUID = body.lastUUID
  try gen(lhs, body)
  let lhsUUID = body.lastUUID
  switch node.opInstructionType {
    case .eq:
      try generateConditional(condition: "Equals", lhsUUID, rhsUUID, invert: false, body)
    case .cmplt:
      if node.op == "<" {
        try generateConditional(condition: "Is Less Than", lhsUUID, rhsUUID, invert: true, body)
      } else {
        try generateConditional(condition: "Is Greater Than", lhsUUID, rhsUUID, invert: false, body)
      }
    default:
      throw parseError(node, "I don't support that operator yet")
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
  var params: [String: Any] = ["WFControlFlowMode": 0, // I think 0 is 'start conditional'
                          "WFCondition": condition]
  if condition == "Equals" {
    params["WFConditionalActionString"] = stringFrom(uuid: rhsUUID)
  } else {
    params["WFNumberValue"] = numberFrom(uuid: rhsUUID)
  }
  body.addExpression(Expression(id: "is.workflow.actions.conditional",
                 params: params, group: group))
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

extension ConditionalStatementNode: ShortcutGeneratable {
  func generate(body: Body) throws {
    let group = UUID().uuidString
    try gen(self.condition, body)
    body.addExpression(Expression(id: "is.workflow.actions.conditional",
                   params: ["WFControlFlowMode": 0, // I think 0 is 'start conditional'
                            "WFCondition": "Equals",
                            "WFConditionalActionString": "TRUE"],
                            group: group))
    try gen(self.body, body)
    body.addExpression(Expression(id: "is.workflow.actions.conditional",
                   params: ["WFControlFlowMode": 1],
                   group: group)) // I think 1 is 'break between if/else'
    if let elseBody = self.elseBody {
      try gen(elseBody, body)
    }
    body.addExpression(Expression(id: "is.workflow.actions.conditional",
                   params: ["WFControlFlowMode": 2],
                   group: group)) // I think 2 is 'endif'
  }
}

extension BodyNode: ShortcutGeneratable {
  func generate(body: Body) throws {
    for node in self.nodes {
      try gen(node, body)
    }
  }
}

extension CallNode: ShortcutGeneratable {
  func generate(body: Body) throws {
    let builtinExists = try addBuiltinAction(node: self, args: arguments, body)
    if builtinExists {
      return
    }
    body.ensureDefined(function: callee)

    if arguments.count > 1 {
      throw parseError(self, "Can't pass more than one argument to functions yet")
    }

    if let argument = arguments.first {
      try gen(argument, body)
    } else {
      body.addExpression(Expression(id: "is.workflow.actions.nothing", params: [:]))
    }

    let argument = body.lastUUID

    let values: [[String: Any]] = [
      [
        "WFItemType": 0,
        // Might need to add more crap here
        "WFKey": methodKey,
        "WFValue": callee
      ],
      [
        "WFItemType": 0,
        // Might need to add more crap here
        "WFKey": functionInputKey,
        "WFValue": stringFrom(uuid: argument)
      ],
    ]

    body.addExpression(
      Expression(id: "is.workflow.actions.dictionary",
                 params: ["WFItems": ["Value": ["WFDictionaryFieldValueItems": values]]]))
    body.addExpression(
      Expression(id: "is.workflow.actions.runworkflow",
                 params: ["WFWorkflowName": try body.program.getWorkflowName()]))
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
    try gen(self.body, newBod)
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

extension DoStatementNode: ShortcutGeneratable {
  func generate(body: Body) throws {
    try gen(self.amount, body)
    let count = body.lastUUID
    let group = UUID().uuidString
    body.addExpression(Expression(id: "is.workflow.actions.repeat.count",
                                  params: [
                                    "WFRepeatCount": numberFrom(uuid: count),
                                    "WFControlFlowMode": 0], group: group))
    try gen(self.body, body)
    body.addExpression(Expression(id: "is.workflow.actions.repeat.count",
                                  params: [
                                    "WFControlFlowMode": 2], group: group))
  }
}
