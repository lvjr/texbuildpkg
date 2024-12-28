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

function fileConcatDir(dir, basename)
  return dir .. tbp.slashsep .. basename
end

function fileGetJobName(file)
  local basename = file:match("/([^/]+)$") or file
  return basename:match("([^%.]+)[%.$]")
end

function fileCopy(basename, srcdir, destdir)
  local c = fileRead(srcdir .. tbp.slashsep .. basename)
  fileWrite(destdir .. tbp.slashsep .. basename, c)
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

checkengines = {"pdftex", "xetex", "luatex"}
checkformat = "latex"
test_order = {"log", "pdf"}
checkruns = 1

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
  cmd = "pdftoppm " .. getimgopt(imgext) .. pdf .. " " .. fileGetJobName(pdf)
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
    pattern = "^" .. fileGetJobName(v):gsub("%-", "%%-") .. "%-%d+%" .. imgext .. "$"
    local imgfiles = fileSearch(dir, pattern)
    if #imgfiles == 1 then
      local imgname = fileGetJobName(v) .. imgext
      if fileExists(dir .. tbp.slashsep .. imgname) then
        fileRemove(dir, imgname)
      end
      fileRename(dir, imgfiles[1], imgname)
      local e = checkOnePdf(dir, fileGetJobName(v)) or 0
      errorlevel = errorlevel + e
    else
      for _, i in ipairs(imgfiles) do
        local e = checkOnePdf(dir, fileGetJobName(i)) or 0
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
    return checkAllFolders(tbparg)
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

-- it equals to total number of failed tests
local errorlevel = main()

--print(errorlevel)

if os.type == "windows" then os.exit(errorlevel) end
