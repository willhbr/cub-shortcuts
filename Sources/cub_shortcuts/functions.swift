import Cub
import Foundation

struct Builtin {
  let name: String
  let id: String
  let builder: ([String]) throws -> [String: Any]
}

class Builtins {
  private static var builtins = [String: Builtin]()
  static func hasBuiltinFunction(name: String) -> Bool {
    return builtins[name] != nil
  }

  static func generateBuiltinFunction(node: CallNode, args: [ASTNode], _ body: Body) throws {
    guard let builtin = builtins[node.callee] else {
      throw ParseError(message: "Function not defined: \(node.callee)", location: nil)
    }
    var uuids = [String]()
    for arg in args {
      try gen(arg, body)
      uuids.append(body.lastUUID)
    }
    let params = try builtin.builder(uuids)
    body.addExpression(Expression(id: builtin.id, params: params))
  }

  static func define(_ name: String, id: String, body: @escaping ([String]) throws -> [String: Any]) {
    guard builtins[name] == nil else {
      // This should never happen IRL
      fatalError("Can't redefine builtin function: \(name)")
    }
    builtins[name] = Builtin(name: name,
                             id: id,
                             builder: body)
  }
}
