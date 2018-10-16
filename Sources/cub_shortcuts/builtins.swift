struct ArgumentError: Error {
  let message: String
}

func registerBuiltins() {
  Builtins.define("alert", id: "is.workflow.actions.alert") { args in
    guard args.count == 2 else {
      throw ArgumentError(message: "alert takes 2 arguments, got \(args.count)")
    }
    let title = args[0]
    let message = args[1]
    return ["WFAlertActionTitle": stringFrom(uuid: title),
            "WFAlertActionMessage": stringFrom(uuid: message)]
  }

  Builtins.define("ask", id: "is.workflow.actions.ask") { args in
    guard (1...2).contains(args.count) else {
      throw ArgumentError(message: "ask takes 1 or 2 arguments, got \(args.count)")
    }
    let title = args[0]
    let type: Any
    if args.count == 2 {
      type = stringFrom(uuid: args[1])
    } else {
      type = "Text"
    }
    return ["WFAskActionPrompt": stringFrom(uuid: title),
            "WFInputType": type]
  }

  Builtins.define("dict", id: "is.workflow.actions.dictionary") { args in
    if args.count % 2 != 0 {
      throw ArgumentError(message: "dict must take even number of args")
    }
    var values = [[String: Any]]()
    for idx in stride(from: 0, through: args.count - 1, by: 2) {
      let keyUUID = args[idx]
      let valueUUID = args[idx + 1]
      values.append([
        "WFItemType": 0,
        "WFKey": stringFrom(uuid: keyUUID),
        "WFValue": stringFrom(uuid: valueUUID)
      ])
    }
    return [
      "WFItems": ["Value": ["WFDictionaryFieldValueItems": values]]
    ]
  }
}
