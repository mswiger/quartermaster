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

local BASE = (...):match("(.-)[^%.]+$")

local class = require(BASE .. "class")

local function loadLoader(loaderModule)
  return {
    loaderModule = loaderModule,
    load = require(loaderModule).load,
    process = require(loaderModule).process or function (data) return data end,
  }
end

local function unpackAssetDescriptor(asset)
  local path, params
  if type(asset) == "table" then
    path = asset.path
    params = asset.params
  elseif type(asset) == "string" then
    path = asset
  else
    return nil
  end

  return path, params
end

local function hashAssetDescriptor(asset)
  local path, params = unpackAssetDescriptor(asset)
  local output = path

  if params then
    for k, v in pairs(params) do
      output = output .. "|" .. k .. "=" .. v
    end
  end

  return output
end

local Quartermaster = class {
  init = function (self)
    self.cache = {}
    self.loaders = {}
    self.inProgressCount = 0

    self.intakeChannel = love.thread.getChannel("quartermaster.intake")
    self.outputChannel = love.thread.getChannel("quartermaster.output")

    self.worker = love.thread.newThread((BASE:gsub("%.", "/").."worker.lua"))
    self.worker:start(self.intakeChannel, self.outputChannel)
  end,

  registerDefaultLoaders = function(self)
    self:registerLoader({ ".bmp", ".jpeg", ".jpg", ".png", ".tga" }, BASE .. "loaders.image")
    self:registerLoader({ ".flac", ".mp3", ".ogg", ".wav" }, BASE .. "loaders.audio")
    self:registerLoader({ ".fnt", ".ttf", ".otf" }, BASE .. "loaders.font")
  end,

  get = function (self, descriptor)
    local assetKey = hashAssetDescriptor(descriptor)
    return self.cache[assetKey]
  end,

  load = function (self, descriptor)
    local path, params = unpackAssetDescriptor(descriptor)

    if path == nil then
      return nil, "Invalid asset descriptor"
    end

    if love.filesystem.getInfo(path) == nil then
      return nil, path .. " does not exist"
    end

    local loader = self:getLoader(path)

    if loader == nil then
      return nil, "No loader registered for the extension of " .. path
    end

    local assetKey = hashAssetDescriptor(descriptor)
    if self.cache[assetKey] then
      return self.assetKey
    end

    local request = {
      path = path,
      params = params,
      loaderModule = loader.loaderModule,
    }

    self.inProgressCount = self.inProgressCount + 1
    self.intakeChannel:push(request)

    return request
  end,

  loadList = function (self, descriptors)
    local successfulRequests = {}
    local failedRequests = {}

    for _, descriptor in ipairs(descriptors) do
      local request, errorMsg = self:load(descriptor)

      if request then
        table.insert(successfulRequests, request)
      end

      if errorMsg then
        table.insert(failedRequests, {
          descriptor = descriptor,
          error = errorMsg,
        })
      end
    end

    if #failedRequests < 1 then
      failedRequests = nil
    end

    return successfulRequests, failedRequests
  end,

  unload = function (self, descriptor)
    self.cache[hashAssetDescriptor(descriptor)] = nil
  end,

  unloadList = function (self, descriptors)
    for _, descriptor in ipairs(descriptors) do
      self:unload(descriptor)
    end
  end,

  unloadAll = function (self)
    self.cache = {}
  end,

  registerLoader = function (self, extension, loaderModule)
    if type(extension) == "table" then
      for _, e in ipairs(extension) do
        self.loaders[e] = loadLoader(loaderModule)
      end
    else
      self.loaders[extension] = loadLoader(loaderModule)
    end
  end,

  deregisterLoader = function (self, extension)
    self.loaders[extension] = nil
  end,

  deregisterAllLoaders = function (self)
    self.loaders = {}
  end,

  sync = function (self, limit)
    while self.outputChannel:peek() do
      local response = self.outputChannel:pop()
      local assetKey = hashAssetDescriptor(response)
      local loader = self:getLoader(response.path)

      if assetKey == nil then
        return nil, "Invalid response from worker"
      end

      self.inProgressCount = self.inProgressCount - 1
      self.cache[assetKey] = loader.process(response.asset)

      if response.dependencies then
        for _, dependency in ipairs(response.dependencies) do
          self:load(dependency.path, dependency.params)
        end
      end

      if limit then
        if limit > 0 then
          limit = limit - 1
        else
          return
        end
      end
    end
  end,

  blockUntilLoaded = function (self)
    while self.inProgressCount > 0 do
      self:sync()
      love.timer.sleep(0.001)
    end
  end,

  shutdown = function(self)
    self:deregisterAllLoaders()
    self:unloadAll()

    self.inProgressCount = 0
    self.intakeChannel:clear()
    self.outputChannel:clear()

    self.intakeChannel:push("exit")
    self.worker:wait()
  end,

  getLoader = function (self, path)
    local extension = path
    local loader = nil

    repeat
      extension = extension:sub(2):match("%..+$")
      if self.loaders[extension] then
        loader = self.loaders[extension]
      end
    until loader ~= nil or extension == nil

    return loader
  end,
}

return Quartermaster
