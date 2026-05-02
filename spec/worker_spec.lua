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

local function newIntakeChannel(...)
  local outputs = { ... }
  return {
    demand = function ()
      if #outputs > 0 then
        return table.remove(outputs)
      else
        return "exit"
      end
    end
  }
end

local function runWorker(intakeChannel, outputChannel)
  local worker = assert(loadfile("worker.lua"))
  return worker(intakeChannel, outputChannel)
end

describe("worker", function ()
  local outputChannel = {
    push = spy.new(function () end)
  }

  it("loads and outputs the requested asset with the given loader", function ()
    local intakeChannel = newIntakeChannel({
      loaderModule = "loaders.dummy",
      path = "some/path",
      params = { p1 = "param1", p2 = "param2" }
    })

    runWorker(intakeChannel, outputChannel)

    assert.spy(outputChannel.push).called_with(outputChannel, {
      asset = "dummy",
      path = "some/path",
      params = { p1 = "param1", p2 = "param2" },
      dependencies = { "other-dummy" },
    })
  end)

  it("returns 0 when the intake message is 'exit'", function ()
    local intakeChannel = newIntakeChannel("exit")
    assert.are.equal(0, runWorker(intakeChannel, outputChannel))
  end)
end)
