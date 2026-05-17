--[[
Copyright (c) 2026 Michael Swiger

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
]]--

-- channels are provided by thread creator
local intakeChannel, outputChannel = ...
local loaders = {}

local function callAndCatch(f)
  local success, err = pcall(f)

  if not success then
    print(err)
  end
end

while true do
  local request = intakeChannel:demand()

  if request == "exit" then
    return 0
  end

  local loaderModule = request.loaderModule
  local path = request.path
  local params = request.params or {}

  if not loaders[loaderModule] then
    callAndCatch(function()
      loaders[loaderModule] = require(loaderModule)
    end)
  end

  local data, dependencies
  callAndCatch(function()
    data, dependencies = loaders[loaderModule].load(path, params)
  end)

  outputChannel:push({
    data = data,
    path = path,
    params = params,
    dependencies = dependencies or {},
  })
end
