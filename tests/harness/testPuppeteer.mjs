import puppeteer from 'puppeteer'

async function run() {
  const browser = await puppeteer.launch({ headless: true })
  const page = await browser.newPage()
  await page.setContent('<canvas id="c" width="100" height="100"></canvas>')
  const pixel = await page.evaluate(() => {
    const c = document.getElementById('c')
    const ctx = c.getContext('2d')
    ctx.fillStyle = '#D6FF62'
    ctx.fillRect(0, 0, 100, 100)
    const data = ctx.getImageData(10, 10, 1, 1).data
    return [data[0], data[1], data[2], data[3]]
  })
  console.log('Canvas pixel from Puppeteer:', pixel)
  await browser.close()
}

run().catch(console.error)
