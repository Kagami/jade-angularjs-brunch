jade = require 'jade'
sysPath = require 'path'
mkdirp  = require 'mkdirp'
fs = require 'fs'

fileWriter = (newFilePath) -> (err, content) ->
  throw err if err?
  return if not content?
  dirname = sysPath.dirname newFilePath
  mkdirp dirname, '0775', (err) ->
    throw err if err?
    fs.writeFile newFilePath, content, (err) -> throw err if err?

module.exports = class JadeAngularJsCompiler
  brunchPlugin: yes
  type: 'template'
  extension: 'jade'

  constructor: (config) ->
    @separator = if config.optimize then "" else "\n\n"
    @public = config.paths.public
    @pretty = !!config.plugins?.jade?.pretty
    @doctype = config.plugins?.jade?.doctype or "5"
    @locals = config.plugins?.jade_angular?.locals
    @modulesFolder = config.plugins?.jade_angular?.modules_folder
    @compileTrigger = sysPath.normalize @public + sysPath.sep + (config.paths.jadeCompileTrigger or 'js/dontUseMe')

  compile: (data, path, callback) ->
    try
      content = jade.compile data,
        compileDebug: no,
        client: no,
        filename: path,
        pretty: @pretty,
        doctype: @doctype
    catch err
      error = err
    finally
      callback error, ""

  preparePair: (pair) ->
    pair.path.push(pair.path.pop()[...-@extension.length] + 'html')
    pair.path.splice 0, 1, @public

  writeStatic: (pair) ->
    @preparePair pair
    writer = fileWriter sysPath.join.apply(this, pair.path)
    writer null, pair.result

  setupModule: (pair) ->
    @preparePair pair
    moduleName = 'partials'
    modulePath = [@public, 'static', 'js', "#{moduleName}.js"].join sysPath.sep
    virtualPath = "/#{moduleName}/#{pair.path[2..].join '/'}"
    content = pair.result
    {moduleName, modulePath, virtualPath, content}

  writeModules: (modules) ->
    for own moduleName, templates of modules
      content = [
        "angular.module('#{moduleName}',[])"
        ".run(['$templateCache',function(t){"
        @separator
      ]
      templates.map (e) =>
        partial = e.content.replace /'/g, "\\'"
        content.push "t.put('#{e.virtualPath}','#{partial}');#{@separator}"
      content.push "}]);"
      content = content.join ""

      writer = fileWriter templates[0].modulePath
      writer null, content

  #TODO: сделать async
  prepareResult: (compiled) ->
    pathes = (result.sourceFiles for result in compiled when result.path is @compileTrigger)[0]

    return [] if pathes is undefined

    pathes.map (e, i) =>
        data = fs.readFileSync e.path, 'utf8'
        content = jade.compile data,
          compileDebug: no,
          client: no,
          filename: e.path,
          pretty: @pretty,
          doctype: @doctype

        result =
          path: e.path.split sysPath.sep
          result: content @locals

  onCompile: (compiled) ->
    preResult = @prepareResult compiled

    @writeStatic pair for pair in preResult \
      when pair.path.indexOf(@modulesFolder) is -1 and \
        pair.path.indexOf('assets') is -1

    modulesRows = (@setupModule pair for pair in preResult \
      when pair.path.indexOf(@modulesFolder) > -1 and \
        pair.path.indexOf('assets') is -1)

    modules = {}
    modulesRows.map (element, index) ->
      if Object.keys(modules).indexOf(element.moduleName) is -1
        modules[element.moduleName] = []
      modules[element.moduleName].push(element)

    @writeModules modules
