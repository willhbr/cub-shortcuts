import Cub
import Foundation

func compileAndWrite(filePath: String) throws {
  registerBuiltins()
  let url = URL(fileURLWithPath: filePath)
  let source = try String(contentsOf: url, encoding: .utf8)
  let lexer = Lexer(input: source)
  let tokens = lexer.tokenize()

  let parser = Parser(tokens: tokens)
  let tree = try! parser.parse()

  let body = Body()
  for node in tree {
      try gen(node, body)
  }
  let encoded = try makeProgram(body: body)

  let data = try PropertyListSerialization.data(fromPropertyList: encoded,
                                                format: .binary, options: 0)
  let name = try body.program.getWorkflowName()
  print("Compiled \(name).shortcut")
  try data.write(to: URL(fileURLWithPath: name + ".shortcut"))
}

if CommandLine.arguments.count != 2 {
  print("usage: cub_shortcuts <file>.cub")
} else {
  let filename = CommandLine.arguments[1]
  do {
    try compileAndWrite(filePath: filename)
  } catch {
    print(error)
  }
}
