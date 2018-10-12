import Cub
import Foundation

let source = """
func foo(a, b, c) returns {
  alert("The number is two", c)
  return a + b + c
}
"""

let lexer = Lexer(input: source)
let tokens = lexer.tokenize()

let parser = Parser(tokens: tokens)
let tree = try! parser.parse()

print(tree)

let body = Body()
for node in tree {
  gen(node, body)
}

let encoded = body.encode()
print(encoded)

let data = try! PropertyListSerialization.data(fromPropertyList: encoded, format: .xml, options: 0)
try! data.write(to: URL(fileURLWithPath: "generated.shortcut"))

