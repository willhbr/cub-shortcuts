import Cub
import Foundation

let source = """
func main() {
  d = dict(3, 2)
  arr = [1, 2, 3]
}
"""

do {
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

