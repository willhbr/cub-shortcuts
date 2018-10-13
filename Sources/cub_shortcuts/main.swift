import Cub
import Foundation

guard CommandLine.arguments.count > 1 else {
  fatalError("Must be given filename")
}

let filename = CommandLine.arguments[1]

do {
  let url = URL(fileURLWithPath: filename)
  let source = try String(contentsOf: url, encoding: .utf8)
  let lexer = Lexer(input: source)
  let tokens = lexer.tokenize()

  let parser = Parser(tokens: tokens)
  let tree = try! parser.parse()

  let body = Body()
  for node in tree {
      try gen(node, body)
  }
  let encoded = body.encode()
  print(encoded)

  let data = try! PropertyListSerialization.data(fromPropertyList: encoded, format: .xml, options: 0)
  try data.write(to: URL(fileURLWithPath: "generated.shortcut"))
} catch {
  print(error)
}

