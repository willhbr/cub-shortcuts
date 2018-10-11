import Cub

let source = """
a = [1, 2, 3]
b = "1 2 3"
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

print(body.encode())
// let data = try! PropertyListSerialization.data(fromPropertyList: encoded, format: .xml, options: 0)
// try! data.write(to: URL(fileURLWithPath: "/Users/will/tmp/shortcuts/generated.shortcut"))
// let encoded = program.encodeProgram()
// print(encoded)

