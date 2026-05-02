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

local Quartermaster = require("quartermaster")
local class = require("class")

-- Test implementation for love channels
local DummyChannel = class {
  init = function (self)
    self.values = {}
  end,

  clear = function (self)
    self.values = {}
  end,

  peek = function (self)
    return self.values[1]
  end,

  pop = function (self)
    return table.remove(self.values, 1)
  end,

  push = function (self, v)
    table.insert(self.values, v)
  end,
}

local intakeChannel = DummyChannel()
local outputChannel = DummyChannel()

-- Stub all the love code used in Quartermaster.
_G.love = {}
_G.love.filesystem = {
  getInfo = function(path)
    if path == "non-existent-file.txt" then
      return nil
    end
    return {}
  end
}
_G.love.thread = {
  getChannel = function(name)
    if name == "quartermaster.intake" then
      return intakeChannel
    elseif name == "quartermaster.output" then
      return outputChannel
    end
  end,

  newThread = function ()
    return {
      start = function () end,
      wait = function () end,
    }
  end,
}
_G.love.timer = {
  sleep = function () end,
}

local function runFakeWorker()
  while intakeChannel:peek() do
    local request = intakeChannel:pop()
    outputChannel:push({
      asset = "dummy",
      dependencies = { path = "other-dummy.txt", params = { p2 = "param2" } },
      path = request.path,
      params = request.params,
    })
  end
end

describe("Quartermaster", function ()
  local quartermaster = Quartermaster()

  before_each(function ()
    quartermaster:registerLoader(".txt", "loaders.dummy")
  end)

  after_each(function ()
    quartermaster:shutdown()
    intakeChannel:clear()
    outputChannel:clear()
  end)

  describe(":get", function ()
    it("returns nil for asset that has not been loaded yet", function ()
      assert.are.equal(nil, quartermaster:get("spec/dummy.txt"))
    end)

    it("returns the loaded asset with the given path and params", function ()
      local descriptor = {
        path = "dummy.txt",
        params = { p = "v" },
      }
      quartermaster:load(descriptor)

      runFakeWorker()
      quartermaster:blockUntilLoaded()

      assert.are.equal(
        "dummy",
        quartermaster:get(descriptor)
      )
    end)
  end)

  describe(":load", function ()
    it("returns the request for the asset to be loaded", function ()
      local descriptor = {
        path = "dummy.txt",
        params = { p = "v" },
      }
      local request = quartermaster:load(descriptor)

      assert.are.same({
        path = descriptor.path,
        params = descriptor.params,
        loaderModule = "loaders.dummy",
      }, request)
    end)

    it("adds the asset to be loaded to the intake channel", function ()
      local descriptor = {
        path = "dummy.txt",
        params = { p = "v" },
      }

      quartermaster:load(descriptor)

      assert.are.same({
        path = descriptor.path,
        params = descriptor.params,
        loaderModule = "loaders.dummy",
      }, intakeChannel:peek())
    end)

    it("returns nil + error when file does not exist", function ()
      local asset, error = quartermaster:load("non-existent-file.txt")
      assert.are.equal(nil, asset)
      assert.are.equal("non-existent-file.txt does not exist", error)
    end)

    it("returns nil + error when no loader has been registered for file", function ()
      local asset, error = quartermaster:load("dummy.obj")
      assert.are.equal(nil, asset)
      assert.are.equal("No loader registered for the extension of dummy.obj", error)
    end)

    it("does not add the asset to the intake channel if it is already loaded", function ()
      quartermaster:load("dummy.txt", { p = "v" })
      runFakeWorker()
      quartermaster:blockUntilLoaded()

      quartermaster:load("dummy.txt", { p = "v" })
      assert.are.equal(nil, intakeChannel:peek())
    end)
  end)

  describe(":loadList", function ()
    it("returns a list of successful requests", function ()
      local descriptor1 = "dummy1.txt"
      local descriptor2 = {
        path = "dummy2.txt",
        params = { p2 = "v2" },
      }

      local requests = quartermaster:loadList({ descriptor1, descriptor2 })
      assert.are.same({
        {
          path = descriptor1,
          params = nil,
          loaderModule = "loaders.dummy",
        },
        {
          path = descriptor2.path,
          params = descriptor2.params,
          loaderModule = "loaders.dummy",
        },
      }, requests)
    end)

    it("adds each of the assets to be loaded to the intake channel", function ()
      local descriptor1 = {
        path = "dummy1.txt",
        params = { p1 = "v1" },
      }
      local descriptor2 = {
        path = "dummy2.txt",
        params = { p2 = "v2" },
      }

      quartermaster:loadList({ descriptor1, descriptor2 })

      assert.are.same({
          path = descriptor1.path,
          params = descriptor1.params,
          loaderModule = "loaders.dummy",
        },
        intakeChannel:pop()
      )

      assert.are.same({
          path = descriptor2.path,
          params = descriptor2.params,
          loaderModule = "loaders.dummy",
        },
        intakeChannel:pop()
      )
    end)

    it("returns a list of failed requests alongside successful requests if there are failures", function ()
      local descriptor1 = {
        path = "dummy1.txt",
        params = { p1 = "v1" },
      }
      local descriptor2 = {
        path = "dummy2.obj",
        params = { p2 = "v2" },
      }

      local successful, failed = quartermaster:loadList({ descriptor1, descriptor2 })

      assert.are.same({
        {
          path = descriptor1.path,
          params = descriptor1.params,
          loaderModule = "loaders.dummy",
        }
      }, successful)

      assert.are.same({
        {
          descriptor = descriptor2,
          error = "No loader registered for the extension of dummy2.obj",
        },
      }, failed)
    end)
  end)

  describe(":unload", function ()
    it("unloads the given asset path if it is loaded", function ()
      quartermaster:load("dummy.txt")
      runFakeWorker()
      quartermaster:blockUntilLoaded()

      assert.Not.Nil(quartermaster:get("dummy.txt"))

      quartermaster:unload("dummy.txt")

      assert.Nil(quartermaster:get("dummy.txt"))
    end)

    it("unloads the given asset descriptor if it is loaded", function ()
      local descriptor = {
        path = "dummy.txt",
        params = { p = "v" },
      }

      quartermaster:load(descriptor)
      runFakeWorker()
      quartermaster:blockUntilLoaded()

      assert.Not.Nil(quartermaster:get(descriptor))

      quartermaster:unload(descriptor)

      assert.Nil(quartermaster:get(descriptor))
    end)
  end)

  describe(":unloadList", function ()
    it("unloads the list of descriptors", function ()
      local descriptor1 = "dummy1.txt"
      local descriptor2 = {
        path = "dummy2.txt",
        params = { p = "v" },
      }

      quartermaster:loadList({ descriptor1, descriptor2 })
      runFakeWorker()
      quartermaster:blockUntilLoaded()

      assert.Not.Nil(quartermaster:get(descriptor1))
      assert.Not.Nil(quartermaster:get(descriptor2))

      quartermaster:unloadList({ descriptor1, descriptor2 })

      assert.Nil(quartermaster:get(descriptor1))
      assert.Nil(quartermaster:get(descriptor2))
    end)
  end)

  describe(":unloadAll", function ()
    it("unloads the entire cache", function ()
      local descriptor1 = "dummy1.txt"
      local descriptor2 = {
        path = "dummy2.txt",
        params = { p = "v" },
      }

      quartermaster:loadList({ descriptor1, descriptor2 })
      runFakeWorker()
      quartermaster:blockUntilLoaded()

      assert.Not.Nil(quartermaster:get(descriptor1))
      assert.Not.Nil(quartermaster:get(descriptor2))

      quartermaster:unloadAll()

      assert.Nil(quartermaster:get(descriptor1))
      assert.Nil(quartermaster:get(descriptor2))
    end)
  end)

  describe(":registerLoader", function ()
    it("successfully registers the given loader", function ()
      quartermaster:registerLoader(".bin", "loaders.dummy")
      local request = quartermaster:load("test.bin")
      assert.Not.Nil(request)
    end)
  end)

  describe(":deregisterLoader", function ()
    it("successfully deregisters the given loader", function ()
      quartermaster:registerLoader(".bin", "loaders.dummy")
      local request1 = quartermaster:load("test.bin")
      assert.Not.Nil(request1)

      quartermaster:deregisterLoader(".bin")
      local request2 = quartermaster:load("test.bin")
      assert.Nil(request2)
    end)
  end)

  describe(":deregisterAllLoaders", function ()
    it("successfully deregisters all loaders", function ()
      quartermaster:registerLoader(".bin", "loaders.dummy")
      local success1 = quartermaster:load("test.bin")
      assert.Not.Nil(success1)

      quartermaster:registerLoader(".obj", "loaders.dummy")
      local success2 = quartermaster:load("test.bin")
      assert.Not.Nil(success2)

      quartermaster:deregisterAllLoaders()

      local failed1 = quartermaster:load("test.bin")
      assert.Nil(failed1)

      local failed2 = quartermaster:load("test.obj")
      assert.Nil(failed2)
    end)
  end)

  describe(":sync", function ()
    it("syncs loaded assets from the worker to the main asset manager", function ()
      local descriptor = {
        path = "dummy.txt",
        params = { p = "v" },
      }
      quartermaster:load(descriptor)

      runFakeWorker()
      quartermaster:sync()

      assert.are.equal(
        "dummy",
        quartermaster:get(descriptor)
      )
    end)
  end)

  describe(":blockUntilLoaded", function ()
    it("blocks until all resources have been loaded", function ()
    local descriptor1 = "dummy1.txt"
      local descriptor2 = {
        path = "dummy2.txt",
        params = { p = "v" },
      }
      quartermaster:loadList({ descriptor1, descriptor2 })

      runFakeWorker()
      quartermaster:blockUntilLoaded()

      assert.are.equal("dummy", quartermaster:get(descriptor1))
      assert.are.equal("dummy", quartermaster:get(descriptor2))
    end)
  end)

  describe(":shutdown", function ()
    it("clears the loaded assets and unregisters all loaders", function ()
      local descriptor1 = {
        path = "dummy1.txt",
        params = { p1 = "v1" },
      }
      local descriptor2 = {
        path = "dummy2.txt",
        params = { p2 = "v2" },
      }

      quartermaster:loadList({ descriptor1, descriptor2 })
      runFakeWorker()
      quartermaster:blockUntilLoaded()

      assert.are.equal("dummy", quartermaster:get(descriptor1))
      assert.are.equal("dummy", quartermaster:get(descriptor2))

      quartermaster:shutdown()

      assert.Nil(quartermaster:get(descriptor1))
      assert.Nil(quartermaster:get(descriptor2))

      local request = quartermaster:load("dummy.txt")
      assert.Nil(request)
    end)

    it("sends the exit signal to the worker", function ()
      quartermaster:shutdown()
      assert.are.equal("exit", intakeChannel:pop())
    end)
  end)

  describe(":getLoader", function ()
    it("returns the loader registered to the given extension", function ()
      local dummyLoader = require("loaders.dummy")
      quartermaster:registerLoader(".bin", "loaders.dummy")

      local loader = quartermaster:getLoader("test.bin")
      assert.are.same({
        loaderModule = "loaders.dummy",
        load = dummyLoader.load,
        process = dummyLoader.process,
      }, loader)
    end)
  end)
end)
