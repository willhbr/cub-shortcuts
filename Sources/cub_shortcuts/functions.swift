import Cub

func addBuiltinAction(name: String, args: [ASTNode], _ body: Body) -> Bool {
  switch name {
  case "alert":
    if args.count != 2 {
      fatalError("alert takes two arguments")
    }
    gen(args[0], body)
    let title = body.lastUUID
    gen(args[1], body)
    let message = body.lastUUID
    let alert = Expression(id: "is.workflow.actions.alert",
                           params: [
                             "WFAlertActionTitle": stringFrom(uuid: title),
                             "WFAlertActionMessage": stringFrom(uuid: message)
                           ], body)
    body.addExpression(alert)
  default:
    return false
  }
  return true
}
