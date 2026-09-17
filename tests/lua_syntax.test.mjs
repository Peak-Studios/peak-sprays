import test from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import path from 'node:path'
import { createRequire } from 'node:module'

const require = createRequire(import.meta.url)
const luaparse = require('luaparse')

test('Lua Syntax: All Lua scripts parse cleanly without errors', () => {
  const dirsToCheck = ['shared', 'server', 'client']
  const luaFiles = []

  function collectLua(dir) {
    const entries = fs.readdirSync(dir, { withFileTypes: true })
    for (const ent of entries) {
      const full = path.join(dir, ent.name)
      if (ent.isDirectory()) {
        collectLua(full)
      } else if (ent.isFile() && ent.name.endsWith('.lua')) {
        luaFiles.push(full)
      }
    }
  }

  for (const dir of dirsToCheck) {
    if (fs.existsSync(dir)) {
      collectLua(dir)
    }
  }

  assert.ok(luaFiles.length >= 20, `Expected at least 20 lua files, found ${luaFiles.length}`)

  for (const file of luaFiles) {
    const code = fs.readFileSync(file, 'utf8')
    try {
      luaparse.parse(code, { luaVersion: '5.3' })
    } catch (err) {
      assert.fail(`Syntax error in ${file}: ${err.message}`)
    }
  }
})
