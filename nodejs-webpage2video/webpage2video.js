// Usage: npm install && node webpage2video.js "https://example.com" 1800
// Note: puppeteer and puppeteer-screen-recorder are managed via package.json.
// Ensure FFmpeg is installed on your system.

// Usage: node webpage2video.js "https://staging30.dizplai.com/graphics/#/" 1800
// Should record the graphics output for 1800 seconds (30 mins)
// The filename will be a santized string of the url passed in and the timestamp (time at the start of the recording - only as good as your local system clock)

const puppeteer = require('puppeteer');
//https://www.npmjs.com/package/puppeteer-screen-recorder
//NOTE - NO AUDIO RECORDED DUE TO PACKAGE
const { PuppeteerScreenRecorder } = require('puppeteer-screen-recorder');
var sanitize = require("sanitize-filename");

const vwidth = 1280;
const vheight = 720;

const Config = {
    followNewTab: true,
    fps: 50,
    ffmpeg_Path: null, // Set to null to use system ffmpeg, or provide a full path if necessary
    videoFrame: {
        width: vwidth,
        height: vheight,
      },
    videoCrf: 18,
    videoCodec: 'libx264',
    videoPreset: 'ultrafast',
    videoBitrate: 1000,
    aspectRatio: '16:9',
    recordDurationLimit: 1800,
  };
function sleep(ms) {
    return new Promise((resolve) => {
      setTimeout(resolve, ms);
    });
}
const arg = process.argv;
if (!arg[2]) {
    throw "Please provide URL as a first argument";
}
if (!arg[3]) {
    throw "Please provide duration (in seconds) to record as a second argument";
}

const pageurl = ""+arg[2];
const durationsecond = 0+parseInt(arg[3]);
const event = new Date(); //now
const timestamp = event.toISOString();
const filename = sanitize(pageurl+"__"+timestamp+".mp4");
console.log(pageurl);
console.log(durationsecond);
console.log(timestamp);
console.log(filename);

  (async () => {
    const browser = await puppeteer.launch({headless: 'new'});
    const page = await browser.newPage();
    const recorder = new PuppeteerScreenRecorder(page);
    await page.goto(pageurl);
    await page.setViewport({width: vwidth, height: vheight});
    await recorder.start('./'+filename); // supports extension - mp4, avi, webm and mov
    await sleep(durationsecond*1000);
    await recorder.stop();
    await browser.close();
  })();