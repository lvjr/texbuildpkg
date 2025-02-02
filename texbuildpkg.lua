#!/usr/bin/env texlua

-- Caption   : Another testing and building system for TeX
-- Author    : Jianrui Lyu <tolvjr@163.com>
-- Repository: https://github.com/lvjr/texbuildpkg
-- License   : The LaTeX Project Public License 1.3c

local tbp = tbp or {}

tbp.version = "2025@"
tbp.date = "2025-01-05"

------------------------------------------------------------
--> \section{Some variables and functions}
------------------------------------------------------------

local assert           = assert
local ipairs           = ipairs
local insert           = table.insert
local remove           = table.remove
local match            = string.match
local gsub             = string.gsub

local function valueExists(tab, val)
  for _, v in ipairs(tab) do
    if v == val then return true end
  end
  return false
end

local md5 = require("md5")

local function md5sum(str)
  if str then return md5.sumhexa(str) end
end

local function filesum(name)
  local f = assert(io.open(name, "rb"))
  local s = f:read("*all")
  f:close()
  return md5sum(s)
end

local lfs = require("lfs")

if os.type == "windows" then
  tbp.concat = "&"
  tbp.slashsep = "\\"
  tbp.null = "NUL"
else
  tbp.concat = ";"
  tbp.slashsep = "/"
  tbp.null = "/dev/null"
end

function tbpNormalizePath(path)
  if os.type == "windows" then
    path = path:gsub("/", "\\")
  else
    path = path:gsub("\\", "/")
  end
  return path
end

currentdir = tbpNormalizePath(lfs.currentdir())

function tbpGlobToPattern(glob)
  local pattern = glob:gsub("([%.%-%+])", "%%%1")
    :gsub("%*", "[^/\\]*"):gsub("%?", "[^/\\]")
  return pattern
end

function fileRead(name)
  local f = assert(io.open(name, "rb"))
  local s = f:read("*all")
  f:close()
  return s
end

function fileWrite(name, text)
  local f = assert(io.open(name, "wb"))
  f:write(text)
  f:close()
end

function fileSearch(path, pattern)
  local files = { }
  for entry in lfs.dir(path) do
    if match(entry, pattern) then
      insert(files, entry)
    end
  end
  return files
end

function dirExists(dir)
  return (lfs.attributes(dir, "mode") == "directory")
end

function fileExists(file)
  return (lfs.attributes(file, "mode") == "file")
end

function fileConcatDir(dir, filename)
  return dir .. tbp.slashsep .. filename
end

function fileGetBaseName(file)
  local filename = file:match("/([^/]+)$") or file
  return filename:match("([^%.]+)[%.$]")
end

function fileCopy(filename, srcdir, destdir)
  local c = fileRead(srcdir .. tbp.slashsep .. filename)
  fileWrite(destdir .. tbp.slashsep .. filename, c)
end

function fileCopyGlob(glob, srcdir, destdir)
  local pattern = tbpGlobToPattern(glob)
  local files = fileSearch(srcdir, pattern)
  for _, f in ipairs(files) do
    local c = fileRead(srcdir .. tbp.slashsep .. f)
    fileWrite(destdir .. tbp.slashsep .. f, c)
  end
end

function fileRemove(dir, basename)
  return os.remove(fileConcatDir(dir,basename))
end

function fileRename(dir, srcname, destname)
  return os.rename(fileConcatDir(dir,srcname), fileConcatDir(dir,destname))
end

function tbpGetAbsPath(path)
  if path:sub(1,1) == "." then
    path = currentdir .. tbpNormalizePath(path:sub(2))
  end
  return path
end

function tbpExecute(dir, cmd)
  return os.execute("cd " .. dir .. tbp.concat .. cmd)
end

local function tbpIpairs(list)
  if type(list) == "nil" then
    list = {}
  elseif type(list) ~= "table" then
    list = {list}
  end
  return ipairs(list)
end

local function tbpIpairsGlob(globlist, dir)
  if type(globlist) == "nil" then
    globlist = {}
  elseif type(globlist) ~= "table" then
    globlist = {globlist}
  end
  local list = {}
  dir = dir or maindir
  for _, glob in ipairs(globlist) do
    local pattern = tbpGlobToPattern(glob)
    local items = fileSearch(dir, pattern)
    for _, v in ipairs(items) do
      table.insert(list, v)
    end
  end
  return ipairs(list)
end

local function tbpMakeDir(dirlist)
  for _, dir in tbpIpairs(dirlist) do
    if not dirExists(dir) then
      lfs.mkdir(dir)
    end
  end
end

local function tbpCopyFile(globs, srcdir, destdir)
  for _, g in tbpIpairs(globs) do
    fileCopyGlob(g, srcdir, destdir)
  end
end

------------------------------------------------------------
--> \section{Initialize TeXBuildPkg}
------------------------------------------------------------

options = {
  config = {},
  debug = false,
  engine = {},
  names = {},
  save = false
}

local tbpconfigs = {}

function tbpDeclareConfig(o)
  tbpconfigs[o.name] = {
    base = o.base,
    code = o.code
  }
  if not valueExists(options.config, o.name) then
    table.insert(options.config, o.name)
  end
end

tbpDeclareConfig({
  name = "default",
  code = function()end
})

maindir = "."
builddir = maindir .. "/tbpbuild"

tbpformatcmds = {
  tex = {
    pdftex = "pdfetex", -- require etex
    xetex = "xetex",
    luatex = "luatex"
  },
  latex = {
    pdftex = "pdflatex",
    xetex = "xelatex",
    luatex = "lualatex"
  },
  context = {
    pdftex = "texexec",
    xetex = "texexec --xetex",
    luatex = "context --luatex",
    luametatex = "context"
  }
}

generate_srcdir = "."
generate_srcfiles = {"*.dtx", "*.ins"}
generate_rundir = builddir .. "/generate"
generate_runfiles = {"*.ins"}
generate_exe = "pdftex"

check_pkgdir = "."
check_pkgfiles = {"*.sty", "*.cls"}
check_testfiledir = "./testfiles"
check_rundir = builddir .. "/check"
check_engines = {"pdftex", "xetex", "luatex"}
check_format = "latex"
check_order = {"log", "img"}
check_runs = 1
check_nlogsubs = {
  {"%(%./", "("},
  {"( on input line )%d+", "%1..."},
  {"(\n\\[^\n=]+=\\box)%d+\n", "%1...\n"},
  {"(\n\\[^\n=]+=\\count)%d+\n", "%1...\n"},
  {"(\n\\[^\n=]+=\\dimen)%d+\n", "%1...\n"},
  {"(\n\\[^\n=]+=\\skip)%d+\n", "%1...\n"},
  {"(\nl%.)%d+ ", "%1 ..."},
  {"\n{[^}]+}", "\n"} -- enc file names
}

typeset_docdir = "."
typeset_docfiles = {"*.dtx", "*.tex"}
typeset_rundir = builddir .. "/typeset"
typeset_exe = "pdflatex"
typeset_runs = 3

texext = ".tex"
logext = ".log"
nlogext = ".nlog"
pdfext = ".pdf"
imgext = ".png"

if os.type == "windows" then
  diffext = ".fc"
  diffexe = "fc /n"
else
  diffext = ".diff"
  diffexe = "diff -c --strip-trailing-cr"
end

dofile("tbpbuild.lua")

maindir = tbpGetAbsPath(maindir)
builddir = tbpGetAbsPath(builddir)

check_testfiledir = tbpGetAbsPath(check_testfiledir)
check_rundir = tbpGetAbsPath(check_rundir)

testcfgname = "regression-test"
cfgext = ".cfg"

-- it equals to total number of failed tests
errorlevel = 0

------------------------------------------------------------
--> \section{Create TeXBuildPkg Objects}
------------------------------------------------------------

TbpFile = {}

function TbpFile:new(filename, config)
  local o = {
    config = config,
    filename = filename,
    basename = fileGetBaseName(filename)
  }
  setmetatable(o, self)
  self.__index = self
  return o
end

function TbpFile:copy(srcdir, destdir)
  fileCopy(self.filename, srcdir, destdir)
  self.srcdir = srcdir
  self.destdir = destdir
  return self
end

------------------------------------------------------------
--> \section{Compile TeX files}
------------------------------------------------------------

local optn = "--interaction=nonstopmode"

local function makeCmdString(prog, name)
  return prog .. " " .. optn .. " " .. name .. " >" .. tbp.null
end

local function texCompileOne(dir, prog, name)
  local cmd = makeCmdString(prog, name)
  return tbpExecute(dir, cmd)
end

function TbpFile:tex(engine, prog)
  texCompileOne(self.destdir, prog, self.filename)
  self.engine = engine
  self.prog = prog
  return self
end

------------------------------------------------------------
--> \section{Generate package files from dtx files}
------------------------------------------------------------

local function tbpGenerate()
  local dir = generate_rundir
  tbpMakeDir(dir)
  tbpCopyFile(generate_srcfiles, generate_srcdir, dir)
  for _, glob in ipairs(generate_runfiles) do
    local pattern = tbpGlobToPattern(glob)
    local filenames = fileSearch(dir, pattern)
    for _, f in ipairs(filenames) do
      print("Unpack " .. f)
      texCompileOne(dir, generate_exe, f)
    end
  end
end

------------------------------------------------------------
--> \section{Log-based regression tests}
------------------------------------------------------------

local dashlines = "============================================================"

function TbpFile:normalizeLogFile()
  local dir = self.destdir
  local basename = self.basename
  local file = dir .. tbp.slashsep .. basename .. logext
  local text = fileRead(file)
  text = text:gsub("\r\n", "\n")
  local t = text:match("START%-TEST%-LOG\n+(.+)\nEND%-TEST%-LOG")
  if t then
    text = t
  else
    text = text:match("\n(" .. dashlines .. "\n.+)\nEND%-TEST%-LOG")
  end
  if text == nil then
    error("Could not make nlog file for " .. basename)
  end
  --- normalize nlog file
  for _, v in ipairs(check_nlogsubs) do
    text = text:gsub(v[1], v[2])
  end
  --- remove empty lines
  local t = ""
  for line, eol in text:gmatch("([^\n]*)([\n$])") do
    if not line:match("^ *$") then
      t = t .. line .. eol
    end
  end
  text = t
  file = dir .. tbp.slashsep .. basename .. "." .. self.engine .. nlogext
  fileWrite(file, text)
  self.newnlog = text
  return self
end

function TbpFile:compareLogFiles()
  local oldfile = self.srcdir .. tbp.slashsep .. self.basename .. nlogext
  local oldnlog = ""
  if fileExists(oldfile) then
    oldnlog = fileRead(oldfile)
    oldnlog = oldnlog:gsub("\r\n", "\n")
    if self.newnlog ~= oldnlog then
      local newfile = self.destdir .. tbp.slashsep .. self.basename .. "." .. self.engine .. nlogext
      local diffile = self.basename .. "." .. self.engine .. diffext
      cmd = diffexe .. " " .. oldfile .. " " .. newfile .. ">" .. diffile
      tbpExecute(self.destdir, cmd)
      self.logerror = self.logerror + 1
      if options.save then
        fileWrite(oldfile, self.newnlog)
        print("      --> log file saved")
      end
    end
  else
    fileWrite(oldfile, self.newnlog)
    print("      --> log file created")
  end
  self.newnlog = nil
  return self
end

------------------------------------------------------------
--> \section{Image-based regression tests}
------------------------------------------------------------

local function getimgopt(imgext)
  local imgopt = ""
  if imgext == ".png" then
    imgopt = " -png "
  elseif imgext == ".ppm" then
    imgopt = " "
  elseif imgext == ".pgm" then
    imgopt = " -gray "
  elseif imgext == ".pbm" then
    imgopt = " -mono "
  else
    error("unsupported image extension" .. imgext)
  end
  return imgopt
end

local function pdftoimg(path, pdf)
  cmd = "pdftoppm " .. getimgopt(imgext) .. pdf .. " " .. fileGetBaseName(pdf)
  tbpExecute(path, cmd)
end

local function saveImgMd5(dir, imgname, md5file, newmd5)
  fileCopy(imgname, dir, check_testfiledir)
  fileWrite(md5file, newmd5)
  print("      --> img file saved")
end

local function checkOnePdf(dir, base)
  local e = 0
  local imgname = base .. imgext
  local md5file = check_testfiledir .. tbp.slashsep .. base .. ".md5"
  local newmd5 = filesum(dir .. tbp.slashsep .. imgname)
  if fileExists(md5file) then
    local oldmd5 = fileRead(md5file)
    if newmd5 ~= oldmd5 then
      e = 1
      local imgdiffexe = os.getenv("imgdiffexe")
      if imgdiffexe then
        local oldimg = check_testfiledir .. tbp.slashsep .. imgname
        local newimg = dir .. tbp.slashsep .. imgname
        local diffname = base .. ".diff.png"
        local cmd = imgdiffexe .. " " .. oldimg .. " " .. newimg
                    .. " -compose src " .. diffname
        --print("      --> img diff created")
        tbpExecute(dir, cmd)
      end
      if options.save == true then
        saveImgMd5(dir, imgname, md5file, newmd5)
      end
    end
  else
    saveImgMd5(dir, imgname, md5file, newmd5)
  end
  return e
end

function TbpFile:compareImage()
  local base = self.basename
  local dir = self.destdir
  pdftoimg(dir, base .. pdfext)
  local pattern = "^" .. base:gsub("%-", "%%-") .. "%-%d+%" .. imgext .. "$"
  local imgfiles = fileSearch(dir, pattern)
  local e = 0
  if #imgfiles == 1 then
    local imgname = base .. imgext
    if fileExists(dir .. tbp.slashsep .. imgname) then
      fileRemove(dir, imgname)
    end
    fileRename(dir, imgfiles[1], imgname)
    e = checkOnePdf(dir, base)
  else
    for _, i in ipairs(imgfiles) do
      e = e + checkOnePdf(dir, fileGetBaseName(i))
    end
  end
  if e > 0 then
    self.imgerror = self.imgerror + 1
  end
  return self
end

------------------------------------------------------------
--> \section{Check regression files}
------------------------------------------------------------

local function tbpCopyCfg(cfg, realtestdir)
  local filename = testcfgname .. cfgext
  if cfg ~= "default" then
    filename = testcfgname .. "-" .. cfg .. cfgext
  end
  if fileExists(check_testfiledir .. tbp.slashsep .. filename) then
    fileCopy(filename, check_testfiledir, realtestdir)
  end
  if cfg ~= "default" then
    fileRename(realtestdir, filename, testcfgname .. cfgext)
  end
end

local function tbpCheckOne(cfg)
  local realtestdir = check_rundir
  if cfg ~= "default" then
    realtestdir = check_rundir .. cfg
  end
  tbpMakeDir({builddir, realtestdir})
  tbpCopyFile(check_pkgfiles, generate_rundir, realtestdir)
  tbpCopyFile(check_pkgfiles, check_pkgdir, realtestdir)
  tbpCopyCfg(cfg, realtestdir)
  local pattern = "%" .. texext .. "$"
  local files = fileSearch(check_testfiledir, pattern)
  print("Running checks in " .. realtestdir)
  for _, f in ipairs(files) do
    local tbpfile = TbpFile:new(f, cfg):copy(check_testfiledir, realtestdir)
    print("  " .. tbpfile.basename)
    tbpfile.logerror = 0
    for _, engine in ipairs(check_engines) do
      local prog = tbpformatcmds[check_format][engine]
      if not prog then
        error("Could not find cmd for engine '" .. engine
               .. "' and format '" .. check_format .. "'!")
      end
      for i = 1, check_runs do
        tbpfile = tbpfile:tex(engine, prog)
      end
      tbpfile = tbpfile:normalizeLogFile():compareLogFiles()
    end
    if tbpfile.logerror > 0 then
      print("      --> log check failed")
      errorlevel = errorlevel + 1
    end
    tbpfile.imgerror = 0
    tpbfile = tbpfile:compareImage()
    if tbpfile.imgerror > 0 then
      print("      --> img check failed")
    end
    if (tbpfile.logerror > 0 or tbpfile.imgerror > 0) then
      errorlevel = errorlevel + 1
    end
  end
  return errorlevel
end

local function tbpCheck()
  tbpGenerate()
  for _, cfg in ipairs(options.config) do
    local t = tbpconfigs[cfg]
    if t == nil then
      print("Unknown config " .. cfg .. "\n")
    else
      if t.base then
        tbpconfigs[t.base].code()
      end
      t.code()
      tbpCheckOne(cfg)
    end
  end
  return errorlevel
end

------------------------------------------------------------
--> \section{Typeset documentation files}
------------------------------------------------------------

local function tbpTypeset()
  tbpGenerate()
  local dir = typeset_rundir
  tbpMakeDir(dir)
  local files = typeset_docfiles
  tbpCopyFile(check_pkgfiles, generate_rundir, dir)
  tbpCopyFile(check_pkgfiles, check_pkgdir, dir)
  tbpCopyFile(files, generate_rundir, dir)
  tbpCopyFile(files, typeset_docdir, dir)
  for _, glob in ipairs(files) do
    local pattern = tbpGlobToPattern(glob)
    local filenames = fileSearch(dir, pattern)
    for _, f in ipairs(filenames) do
      print("Typeset " .. f)
      for i = 1, typeset_runs do
        texCompileOne(dir, typeset_exe, f)
      end
    end
  end
end

------------------------------------------------------------
--> \section{Print help or version text}
------------------------------------------------------------

local helptext = [[
usage: texbuildpkg <target> [<options>]

valid targets are:
   check        Run tests without saving outputs of failed tests
   save         Run tests and save outputs of failed tests
   help         Print this message and exit
   version      Print version information and exit

valid options are:
   -c           Set the config used for check or save target

please report bug at https://github.com/lvjr/texbuildpkg
]]

local function help()
  print(helptext)
  return 0
end

local function version()
  print("TeXBuildPkg Version " .. tbp.version .. " (" .. tbp.date .. ")\n")
  return 0
end

------------------------------------------------------------
--> \section{Respond to user input}
------------------------------------------------------------

local shortoptions = {
  c = "config",
  e = "engine"
}

local function tbpSetTabOption(key, names)
  options[key] = {}
  for n in names:gmatch("[^,]+") do
    table.insert(options[key], n)
  end
end

local function tbpParseOneOption(key, input)
  local value = options[key]
  if type(value) == "boolean" then
    options[key] = true
  elseif type(value) == "table" then
    return true
  else
    print("Unknown option " .. input .. "\n")
    help()
    os.exit(1)
  end
  return false
end

local function tbpParseOptions(arglist)
  local istabvalue = false
  local key = ""
  for _, item in ipairs(arglist) do
    if istabvalue then
      tbpSetTabOption(key, item)
      istabvalue = false
    elseif item:match("^%-%-") then
      key = item:sub(3)
      istabvalue = tbpParseOneOption(key, item)
    elseif item:match("^%-") then
      key = shortoptions[item:sub(2)]
      istabvalue = tbpParseOneOption(key, item)
    else
      tbpSetTabOption("names", item)
    end
  end
  if istabvalue then
    print("Missing name(s) for option " .. arglist[#arglist] .. "\n")
    help()
    os.exit(1)
  end
end

local function tbpMain(tbparg)
  if tbparg[1] == nil then return help() end
  local target = remove(tbparg, 1)
  -- remove leading dashes
  target = match(target, "^%-*(.*)$")
  tbpParseOptions(tbparg)
  if target == "check" then
    return tbpCheck()
  elseif target == "save" then
    options.save = true
    return tbpCheck()
  elseif target == "generate" then
    return tbpGenerate()
  elseif target == "typeset" then
    return tbpTypeset()
  elseif target == "help" then
    return help()
  elseif target == "version" then
    return version()
  else
    print("Unknown target '" .. target .. "'\n")
    return help()
  end
end

local function main()
  return tbpMain(arg)
end

main()

--print(errorlevel)

if os.type == "windows" then os.exit(errorlevel) end
