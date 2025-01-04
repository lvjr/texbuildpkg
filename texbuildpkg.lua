#!/usr/bin/env texlua

-- Description: Image-based regression testing for LaTeX packages
-- Copyright: 2024 (c)  Jianrui Lyu <tolvjr@163.com>
-- Repository: https://github.com/lvjr/texbuildpkg
-- License: The LaTeX Project Public License 1.3c

local tbp = tbp or {}

tbp.version = "2025@"
tbp.date = "2024-12-15"

------------------------------------------------------------
--> \section{Some variables and functions}
------------------------------------------------------------

local assert           = assert
local ipairs           = ipairs
local insert           = table.insert
local remove           = table.remove
local match            = string.match
local gsub             = string.gsub

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
  tbp.slashsep = "\\"
  tbp.null = "NUL"
else
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
  lfs.chdir(dir)
  return os.execute(cmd)
end

------------------------------------------------------------
--> \section{Initialize TeXBuildPkg}
------------------------------------------------------------

maindir = "."
builddir = maindir .. "/tbpdir"
testdir = builddir .. "/test"
testfiledir = "./testfiles"

sourcefiles = {}

checkconfigs = {"build"}
checkprograms = {"pdflatex", "xelatex", "lualatex"}
test_order = {"log", "pdf"}
checkruns = 1

moreconfigs = {}

lvtext = ".tex"
tlgext = ".tlg"
logext = ".log"
pdfext = ".pdf"
imgext = ".png"

if os.type == "windows" then
  diffext = ".fc"
  diffexe = "fc /n"
else
  diffext = ".diff"
  diffexe = "diff -c --strip-trailing-cr"
end

dofile("tbpconfig.lua")

maindir = tbpGetAbsPath(maindir)
builddir = tbpGetAbsPath(builddir)
testdir = tbpGetAbsPath(testdir)
testfiledir = tbpGetAbsPath(testfiledir)

testcfgname = "regression-test"
cfgext = ".cfg"

-- it equals to total number of failed tests
errorlevel = 0

------------------------------------------------------------
--> \section{Create TeXBuildPkg Objects}
------------------------------------------------------------

TbpFile = {}

function TbpFile:new(filename)
  local o = {
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

local optn = "--interaction=nonstopmode"

local function makeCmdString(prog, name)
  return prog .. " " .. optn .. " " .. name .. ".tex" .. " >" .. tbp.null
end

local function texCompileOne(dir, prog, name)
  local cmd = makeCmdString(prog, name)
  return tbpExecute(dir, cmd)
end

function TbpFile:tex(prog)
  texCompileOne(self.destdir, prog, self.basename)
  self.prog = prog
  return self
end

function TbpFile:makeTlgFile()
  local dir = self.destdir
  local basename = self.basename
  local file = dir .. tbp.slashsep .. basename .. logext
  local text = fileRead(file)
  text = text:gsub("\r\n", "\n")
             :match("START%-TEST%-LOG\n+(.+)\nEND%-TEST%-LOG")
  if not text then
    error("Could not make tlg file for " .. basename)
  end
  --- normalize tlg file
  text = text:gsub("\n[\n ]*", "\n"):gsub("%(%./", "(")
             :gsub("( on input line )%d+", "%1...")
  file = dir .. tbp.slashsep .. basename .. "." .. self.prog .. tlgext
  fileWrite(file, text)
  local oldfile = testfiledir .. tbp.slashsep .. basename .. tlgext
  return self
end

function TbpFile:compareTlgFiles()
  local oldtlg = self.srcdir .. tbp.slashsep .. self.basename .. tlgext
  local newtlg = self.destdir .. tbp.slashsep .. self.basename .. "." .. self.prog .. tlgext
  local diffile = self.basename .. "." .. self.prog .. diffext
  cmd = diffexe .. " " .. oldtlg .. " " .. newtlg .. ">" .. diffile
  self.error = self.error + tbpExecute(self.destdir, cmd)
  return self
end

------------------------------------------------------------
--> \section{Compile TeX Files}
------------------------------------------------------------

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

local function tbpCopyCfg(cfg, realtestdir)
  local filename = testcfgname .. cfgext
  if cfg ~= "default" then
    filename = testcfgname .. "-" .. cfg .. cfgext
  end
  if fileExists(testfiledir .. tbp.slashsep .. filename) then
    fileCopy(filename, testfiledir, realtestdir)
  end
  if cfg ~= "default" then
    fileRename(realtestdir, filename, testcfgname .. cfgext)
  end
end

local function tbpCheckOne(cfg)
  local realtestdir = testdir
  if cfg ~= "default" then
    realtestdir = testdir .. cfg
  end
  tbpMakeDir({builddir, realtestdir})
  tbpCopyFile(sourcefiles, maindir, realtestdir)
  tbpCopyCfg(cfg, realtestdir)
  local pattern = "%" .. lvtext .. "$"
  local files = fileSearch(testfiledir, pattern)
  print("Running checks in " .. realtestdir)
  for _, f in ipairs(files) do
    local tbpfile = TbpFile:new(f):copy(testfiledir, realtestdir)
    print("  " .. tbpfile.basename)
    tbpfile.error = 0
    for _, prog in ipairs(checkprograms) do
      tbpfile = tbpfile:tex(prog):makeTlgFile():compareTlgFiles()
    end
    if tbpfile.error > 0 then
      print("          --> failed")
      errorlevel = errorlevel + 1
    end
  end
  return errorlevel
end

local function tbpCheck()
  tbpCheckOne("default")
  if #moreconfigs > 0 then
    for _, item in ipairs(moreconfigs) do
      item[2]()
      tbpCheckOne(item[1])
    end
  end
  return errorlevel
end

------------------------------------------------------------
--> \section{Run check or save actions}
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
  print("save md5 and image files for " .. imgname)
  fileCopy(imgname, dir, testfiledir)
  fileWrite(md5file, newmd5)
end

local issave = false

local function checkOnePdf(dir, job)
  local errorlevel
  local imgname = job .. imgext
  local md5file = testfiledir .. tbp.slashsep .. job .. ".md5"
  local newmd5 = filesum(dir .. tbp.slashsep .. imgname)
  if fileExists(md5file) then
    local oldmd5 = fileRead(md5file)
    if newmd5 == oldmd5 then
      errorlevel = 0
      print("md5 check passed for " .. imgname)
    else
      errorlevel = 1
      print("md5 check failed for " .. imgname)
      local imgdiffexe = os.getenv("imgdiffexe")
      if imgdiffexe then
        local oldimg = testfiledir .. tbp.slashsep .. imgname
        local newimg = dir .. tbp.slashsep .. imgname
        local diffname = job .. ".diff.png"
        local cmd = imgdiffexe .. " " .. oldimg .. " " .. newimg
                    .. " -compose src " .. diffname
        print("creating image diff file " .. diffname)
        tbpExecute(dir, cmd)
      elseif issave == true then
        saveImgMd5(dir, imgname, md5file, newmd5)
      end
    end
  else
    errorlevel = 0
    saveImgMd5(dir, imgname, md5file, newmd5)
  end
  return errorlevel
end

local function checkOneFolder(dir)
  print("checking folder " .. dir)
  local errorlevel = 0
  local pattern = "%" .. pdfext .. "$"
  local files = fileSearch(dir, pattern)
  for _, v in ipairs(files) do
    pdftoimg(dir, v)
    pattern = "^" .. fileGetBaseName(v):gsub("%-", "%%-") .. "%-%d+%" .. imgext .. "$"
    local imgfiles = fileSearch(dir, pattern)
    if #imgfiles == 1 then
      local imgname = fileGetBaseName(v) .. imgext
      if fileExists(dir .. tbp.slashsep .. imgname) then
        fileRemove(dir, imgname)
      end
      fileRename(dir, imgfiles[1], imgname)
      local e = checkOnePdf(dir, fileGetBaseName(v)) or 0
      errorlevel = errorlevel + e
    else
      for _, i in ipairs(imgfiles) do
        local e = checkOnePdf(dir, fileGetBaseName(i)) or 0
        errorlevel = errorlevel + e
      end
    end
  end
  return errorlevel
end

local function cfgToDir(cfg)
  if cfg == "build" then
    return testdir
  else
    return testdir .. "-" .. cfg
  end
end

local function checkAllFolders(arglist)
  if arglist[1] == "-c" then
    if arglist[2] then
      return checkOneFolder(cfgToDir(arglist[2]))
    else
      print("missing config name for -c option")
      return 0
    end
  else
    if #checkconfigs == 0 then
      return checkOneFolder(testdir)
    else
      local errorlevel = 0
      for _, v in ipairs(checkconfigs) do
        local dir = cfgToDir(v)
        local e = checkOneFolder(dir) or 0
        errorlevel = errorlevel + e
      end
      return errorlevel
    end
  end
end

------------------------------------------------------------
--> \section{Print help or version text}
------------------------------------------------------------

local helptext = [[
usage: texbuildpkg <action> [<options>]

valid actions are:
   check        Run tests without saving outputs of failed tests
   save         Run tests and save outputs of failed tests
   help         Print this message and exit
   version      Print version information and exit

valid options are:
   -c           Set the config used for check or save action

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

local function tbpMain(tbparg)
  if tbparg[1] == nil then return help() end
  local action = remove(tbparg, 1)
  -- remove leading dashes
  action = match(action, "^%-*(.*)$")
  if action == "check" then
    return tbpCheck(tbparg) + checkAllFolders(tbparg)
  elseif action == "save" then
    issave = true
    return checkAllFolders(tbparg)
  elseif action == "help" then
    return help()
  elseif action == "version" then
    return version()
  else
    print("unknown action '" .. action .. "'\n")
    return help()
  end
end

local function main()
  return tbpMain(arg)
end

main()

--print(errorlevel)

if os.type == "windows" then os.exit(errorlevel) end
