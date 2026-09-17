import test from 'node:test'
import assert from 'node:assert/strict'
import puppeteer from 'puppeteer'
import http from 'node:http'
import fs from 'node:fs'
import path from 'node:path'

test('P1.1 Shared Renderer Headless Canvas: Determinism and Race Safety', async (t) => {
  // Start minimal static HTTP server for ui/dist
  const distDir = path.resolve('ui/dist')
  const mimeTypes = {
    '.html': 'text/html',
    '.js': 'text/javascript',
    '.css': 'text/css',
    '.json': 'application/json',
    '.png': 'image/png',
    '.ttf': 'font/ttf',
    '.woff2': 'font/woff2'
  }

  const server = http.createServer((req, res) => {
    let reqPath = req.url.split('?')[0]
    if (reqPath === '/' || reqPath === '') reqPath = '/canvas.html'
    const filePath = path.join(distDir, reqPath.replace(/^\//, ''))
    if (fs.existsSync(filePath) && fs.statSync(filePath).isFile()) {
      const ext = path.extname(filePath)
      res.writeHead(200, {
        'Content-Type': mimeTypes[ext] || 'application/octet-stream',
        'Access-Control-Allow-Origin': '*'
      })
      fs.createReadStream(filePath).pipe(res)
    } else {
      res.writeHead(404)
      res.end('Not Found')
    }
  })

  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve))
  const port = server.address().port

  const browser = await puppeteer.launch({
    headless: true,
    args: [
      '--no-sandbox',
      '--disable-setuid-sandbox',
      '--disable-web-security'
    ]
  })

  t.after(async () => {
    await browser.close()
    await new Promise((resolve) => server.close(resolve))
  })

  const page = await browser.newPage()
  await page.setViewport({ width: 512, height: 512 })

  // Navigate to DUI canvas page
  await page.goto(`http://127.0.0.1:${port}/canvas.html`, { waitUntil: 'load' })

  // Wait for canvas DUI interface to attach
  await page.waitForFunction(() => window.__PEAK_CANVAS__ !== undefined)

  // Configure canvas dimensions
  await page.evaluate(() => {
    const { canvas } = window.__PEAK_CANVAS__
    canvas.width = 512
    canvas.height = 512
  })

  await t.test('1. Repeated renders of identical document produce 100% identical pixels', async () => {
    const result = await page.evaluate(async () => {
      const { ctx, renderComposition } = window.__PEAK_CANVAS__

      const composition = {
        version: '1.0.0',
        width: 512,
        height: 512,
        layers: [
          {
            id: 'layer_spray_1',
            name: 'Spray Layer',
            type: 'freehand',
            visible: true,
            opacity: 1.0,
            brushStyle: 'spray',
            strokes: [
              {
                type: 'paint',
                style: 'spray',
                color: '#D6FF62',
                size: 20,
                density: 30,
                points: [
                  { x: 100, y: 100 },
                  { x: 150, y: 120 },
                  { x: 200, y: 150 }
                ]
              }
            ]
          }
        ]
      }

      // Pass 1
      await renderComposition(ctx, composition, { clear: true })
      const data1 = Array.from(ctx.getImageData(0, 0, 256, 256).data)

      // Pass 2
      await renderComposition(ctx, composition, { clear: true })
      const data2 = Array.from(ctx.getImageData(0, 0, 256, 256).data)

      let diffCount = 0
      for (let i = 0; i < data1.length; i++) {
        if (data1[i] !== data2[i]) diffCount++
      }

      return { pass1Count: data1.length, diffCount }
    })

    assert.equal(result.diffCount, 0, 'Pixel output between repeated renders must be 100% identical')
  })

  await t.test('2. Reordering layers in stack does not alter layer procedural appearance seeds', async () => {
    const result = await page.evaluate(async () => {
      const { ctx, renderComposition } = window.__PEAK_CANVAS__

      const layerA = {
        id: 'layer_stable_a',
        name: 'Layer A',
        type: 'freehand',
        visible: true,
        opacity: 1.0,
        brushStyle: 'rough_spray',
        strokes: [
          {
            type: 'paint',
            style: 'rough_spray',
            color: '#10B981',
            size: 25,
            points: [{ x: 50, y: 50 }, { x: 80, y: 80 }]
          }
        ]
      }

      const layerB = {
        id: 'layer_stable_b',
        name: 'Layer B',
        type: 'stencil',
        visible: true,
        opacity: 1.0,
        stencilId: 'Star',
        x: 400,
        y: 400,
        size: 50,
        color: '#FFFFFF'
      }

      // Render with Layer A at index 0
      await renderComposition(ctx, {
        version: '1.0.0',
        width: 512,
        height: 512,
        layers: [layerA, layerB]
      }, { clear: true })
      const dataBefore = Array.from(ctx.getImageData(30, 30, 80, 80).data)

      // Render with Layer A reordered to index 1 (Layer B is at 400, 400 so doesn't touch region 30,30)
      await renderComposition(ctx, {
        version: '1.0.0',
        width: 512,
        height: 512,
        layers: [layerB, layerA]
      }, { clear: true })
      const dataAfter = Array.from(ctx.getImageData(30, 30, 80, 80).data)

      let diffCount = 0
      for (let i = 0; i < dataBefore.length; i++) {
        if (dataBefore[i] !== dataAfter[i]) diffCount++
      }

      return { diffCount }
    })

    assert.equal(result.diffCount, 0, 'Reordering layers in stack must not reroll procedural paint seeds')
  })

  await t.test('3. Race safety: Out-of-order render completion aborts without clobbering newer frame', async () => {
    const result = await page.evaluate(async () => {
      const { ctx, renderComposition, getNextGenerationToken } = window.__PEAK_CANVAS__

      const redDoc = {
        version: '1.0.0',
        width: 512,
        height: 512,
        layers: [
          {
            id: 'l_red',
            type: 'freehand',
            visible: true,
            opacity: 1.0,
            brushStyle: 'roller',
            strokes: [
              { type: 'paint', style: 'roller', color: '#EF4444', size: 50, points: [{ x: 80, y: 100 }, { x: 120, y: 100 }] }
            ]
          }
        ]
      }

      const greenDoc = {
        version: '1.0.0',
        width: 512,
        height: 512,
        layers: [
          {
            id: 'l_green',
            type: 'freehand',
            visible: true,
            opacity: 1.0,
            brushStyle: 'roller',
            strokes: [
              { type: 'paint', style: 'roller', color: '#10B981', size: 50, points: [{ x: 80, y: 100 }, { x: 120, y: 100 }] }
            ]
          }
        ]
      }

      const token1 = getNextGenerationToken()
      const token2 = getNextGenerationToken()

      // Render 2 (newer generation) finishes first
      await renderComposition(ctx, greenDoc, { clear: true, generationToken: token2 })

      // Render 1 (older generation) completes afterward
      const accepted1 = await renderComposition(ctx, redDoc, { clear: true, generationToken: token1 })

      // Check pixel at 100, 100
      const pixel = ctx.getImageData(100, 100, 1, 1).data

      return {
        accepted1,
        // Green channel should dominate; Red should not have overwritten it
        r: pixel[0],
        g: pixel[1],
        b: pixel[2]
      }
    })

    assert.equal(result.accepted1, false, 'Older generation token must be rejected')
    assert.ok(result.g > 100, 'Green frame must remain visible')
    assert.ok(result.r < 50, 'Red frame must not have overwritten green frame')
  })

  await t.test('4. World erase mask punches through layers with alpha destination-out', async () => {
    const result = await page.evaluate(async () => {
      const { ctx, renderComposition } = window.__PEAK_CANVAS__

      const maskedDoc = {
        version: '1.0.0',
        width: 512,
        height: 512,
        layers: [
          {
            id: 'l_solid',
            type: 'freehand',
            visible: true,
            opacity: 1.0,
            brushStyle: 'spray',
            strokes: [
              { type: 'paint', color: '#FFFFFF', size: 50, points: [{ x: 200, y: 200 }] }
            ]
          }
        ],
        eraseMask: [
          {
            size: 60,
            points: [{ x: 190, y: 200 }, { x: 210, y: 200 }]
          }
        ]
      }

      await renderComposition(ctx, maskedDoc, { clear: true })
      const pixel = ctx.getImageData(200, 200, 1, 1).data

      return { alpha: pixel[3] }
    })

    assert.equal(result.alpha, 0, 'Center of erase mask must have alpha 0 (erased to transparency)')
  })
})
