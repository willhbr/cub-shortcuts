import Foundation

let methodKey = "__method__"
let functionInputKey = "__input__"
let inputVariable = "input"
let mainFunctionName = "main"

func makeProgram(body: Body) throws -> NSDictionary {
  guard let mainFunc = body.program.functions.removeValue(forKey: mainFunctionName) else {
    throw ParseError(message: "No main function defined", location: nil)
  }
  try body.program.checkFunctions()
  var exp = [Expression]()
  // Keep input
  exp.append(Expression(id: "is.workflow.actions.setvariable",
                        params: ["WFVariableName": mainFunc.arguments.first ?? inputVariable]))
  let inputDict = Expression(id: "is.workflow.actions.detect.dictionary", params: [:])
  exp.append(inputDict)

  exp.append(Expression(id: "is.workflow.actions.getvalueforkey", params: ["WFDictionaryKey": methodKey]))

  var closingGroups = [String]()
  // Generate other functions
  for function in body.program.functions.values {
    let group = UUID().uuidString
    exp.append(Expression(id: "is.workflow.actions.conditional",
                   params: ["WFControlFlowMode": 0,
                            "WFCondition": "Equals",
                            "WFConditionalActionString": function.name],
                            group: group))
    
    for (idx, argument) in function.arguments.enumerated() {
      exp.append(Expression(id: "is.workflow.actions.getvariable",
                            params: ["WFVariable": dictFrom(uuid: inputDict.uuid)]))
      exp.append(Expression(id: "is.workflow.actions.getvalueforkey",
                            params: ["WFDictionaryKey": functionInputKey + String(idx)]))
      exp.append(Expression(id: "is.workflow.actions.setvariable",
                            params: ["WFVariableName": argument]))
    }
    for statement in function.body.statements {
      exp.append(statement)
    }
    exp.append(Expression(id: "is.workflow.actions.conditional",
                          params: ["WFControlFlowMode": 1],
                          group: group))
    closingGroups.append(group)
  }
  // Generate main method

  for statement in mainFunc.body.statements {
    exp.append(statement)
  }

  // Generate closing conditionals
  for group in closingGroups.reversed() {
    exp.append(Expression(id: "is.workflow.actions.conditional",
                          params: ["WFControlFlowMode": 2],
                          group: group))
  }

  return [
    "WFWorkflowActions": exp.map { $0.encode() },
		"WFWorkflowInputContentItemClasses": [ "WFAppStoreAppContentItem", "WFArticleContentItem", "WFContactContentItem", "WFDateContentItem",
    "WFEmailAddressContentItem", "WFGenericFileContentItem", "WFImageContentItem", "WFiTunesProductContentItem",
    "WFLocationContentItem", "WFDCMapsLinkContentItem", "WFAVAssetContentItem", "WFPDFContentItem",
    "WFPhoneNumberContentItem", "WFRichTextContentItem", "WFSafariWebPageContentItem",
    "WFStringContentItem", "WFURLContentItem" ],
    "WFWorkflowTypes": [ "NCWidget", "WatchKit", "ActionExtension" ]
  ]
}

