import Foundation
import Cub


let actionIdentifier = "WFWorkflowActionIdentifier"
let actionParams = "WFWorkflowActionParameters"

class Body {
  var statements = [Expression]()
  var conditionalGroups = [String]()

  var conditionalGroup: String? { return conditionalGroups.last }
  var lastUUID: String { return statements.last!.uuid }

  func addExpression(_ expression: Expression) {
    statements.append(expression)
  }

  func ensureDefined(function: String) {

  }

  func encode() -> NSDictionary {
    return [
      "WFWorkflowActions": statements.map { $0.encode() }
    ]
  }
}

struct Expression {
  let id: String
  let params: [String: Any]
  let uuid: String
  let conditionalGroup: String?

  init(id: String, params: [String: Any], _ body: Body) {
    self.id = id
    self.params = params
    self.conditionalGroup = body.conditionalGroup
    self.uuid = UUID().uuidString
  }

  func encode() -> NSDictionary {
    var dict = params
    if let group = conditionalGroup, id.hasSuffix("conditional") {
      dict["GroupingIdentifier"] = group
    }
    dict["UUID"] = uuid
    return [
      actionIdentifier: id,
      actionParams: dict,
    ]
  }
}

protocol ShortcutGeneratable {
  func generate(body: Body)
}
func gen(_ node: ASTNode, _ body: Body) {
  switch node {
  case let generatable as ShortcutGeneratable:
    generatable.generate(body: body)
  default:
    fatalError("Can't generate \(node)")
  }
}

extension AssignmentNode: ShortcutGeneratable {
  func generate(body: Body) {
    gen(self.value, body)
    switch self.variable {
    case let iden as VariableNode:
      body.addExpression(Expression(id: "is.workflow.actions.setvariable",
        params: ["WFVariableName": iden.name], body))
    default:
      fatalError("Can't assign to \(self.variable)")
    }
  }
}

extension VariableNode: ShortcutGeneratable {
  func generate(body: Body) {
    body.addExpression(
      Expression(id: "is.workflow.actions.getvariable",
                 params: [
                   "WFVariable": [
                     "Value": [
                       "Type": "Variable",
                       "VariableName": name],
                   // Does this depend on the type?
                   "WFSerializationType": "WFTextTokenAttachment"]], body))
  }
}

extension NumberNode: ShortcutGeneratable {
  func generate(body: Body) {
    body.addExpression(Expression(id: "is.workflow.actions.number",
                                  params: ["WFNumberActionNumber": value],
                                  body))
  }
}

extension StringNode: ShortcutGeneratable {
  func generate(body: Body) {
    body.addExpression(Expression(id: "is.workflow.actions.gettext",
                                  params: ["WFTextActionText": value],
                                  body))
  }
}

extension ArrayNode: ShortcutGeneratable {
  func generate(body: Body) {
    // TODO turn this into an actual list
    for value in self.values {
      gen(value, body)
    }
  }
}

extension ArraySubscriptNode: ShortcutGeneratable {
  func generate(body: Body) {
    gen(variable, body)
    gen(name, body)
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
  func generate(body: Body) {
    guard let rhs = self.rhs else {
      fatalError("Can't do unary operators, sorry")
    }
    gen(rhs, body)
    let uuid = body.lastUUID
    gen(lhs, body)
    let op: String
    switch opInstructionType {
    case .add: op = "+"
    case .sub: op = "-"
    case .mul: op = "\u{00d7}"
    case .div: op = "\u{00f7}"
    default: fatalError("I don't support that operator yet")
    }
    body.addExpression(
      Expression(id: "is.workflow.actions.math",
                 params: [
                   "WFMathOperand": numberFrom(uuid: uuid),
                   "WFMathOperation": op], body)
      )
  }
}

extension CallNode: ShortcutGeneratable {
  func generate(body: Body) {
    if !addBuiltinAction(name: callee, args: arguments, body) {
      body.ensureDefined(function: callee)
    }
  }
}
