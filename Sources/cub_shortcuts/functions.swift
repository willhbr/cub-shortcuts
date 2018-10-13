import Cub

func addBuiltinAction(node: CallNode, args: [ASTNode], _ body: Body) throws -> Bool {
  let name = node.callee
  switch name {
  case "alert":
    if args.count != 2 {
      throw parseError(node, "alert takes two arguments")
    }
    try gen(args[0], body)
    let title = body.lastUUID
    try gen(args[1], body)
    let message = body.lastUUID
    let alert = Expression(id: "is.workflow.actions.alert",
                           params: [
                             "WFAlertActionTitle": stringFrom(uuid: title),
                             "WFAlertActionMessage": stringFrom(uuid: message)
                           ], body)
    body.addExpression(alert)
  case "dict":
    if args.count % 2 != 0 {
      throw parseError(node, "Dict must take even number of args")
    }
    var values = [[String: Any]]()
    for idx in stride(from: 0, through: args.count - 1, by: 2) {
      try gen(args[idx], body)
      let keyUUID = body.lastUUID
      try gen(args[idx + 1], body)
      let valueUUID = body.lastUUID
      values.append([
        "WFItemType": 0,
        "WFKey": stringFrom(uuid: keyUUID),
        "WFValue": stringFrom(uuid: valueUUID)
      ])
    }
    let dict = Expression(id: "is.workflow.actions.dictionary",
            params: ["WFItems": ["Value":
              ["WFDictionaryFieldValueItems": values]]], body)
    body.addExpression(dict)
  default:
    return false
  }
  return true
}
