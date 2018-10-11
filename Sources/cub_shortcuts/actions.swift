import Foundation
import Cub


let actionIdentifier = "WFWorkflowActionIdentifier"
let actionParams = "WFWorkflowActionParameters"

class Body {
  var statements = [Expression]()
  var conditionalGroups = [String]()

  var conditionalGroup: String? { return conditionalGroups.last }

  func addExpression(_ expression: Expression) {
    statements.append(expression)
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

// extension BinaryOpNode: ShortcutGeneratable {
//   func generate(body: Body) {
// 
//   }
// }
