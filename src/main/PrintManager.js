const { spawn } = require('child_process');
const path = require('path');
const fs = require('fs');

class PrintManager {
  constructor(resourcesPath, onProgressCallback) {
    this.resourcesPath = resourcesPath;
    this.onProgress = onProgressCallback || (() => {});
    this.isPrinting = false;
    this.logs = [];
  }

  log(msg) {
    const time = new Date().toLocaleTimeString();
    const entry = `[${time}] ${msg}`;
    this.logs.push(entry);
    console.log(entry);
  }

  getLogs() {
    return this.logs;
  }

  /**
   * Print a file (PDF or PostScript) with copy count
   */
  async printFile(filePath, copies = 1) {
    if (this.isPrinting) {
      return { success: false, error: 'A print job is already in progress.' };
    }

    if (!filePath || !fs.existsSync(filePath)) {
      return { success: false, error: 'Selected file does not exist or is unreadable.' };
    }

    const copiesNum = parseInt(copies, 10);
    if (isNaN(copiesNum) || copiesNum < 1 || copiesNum > 99) {
      return { success: false, error: 'Copies count must be a number between 1 and 99.' };
    }

    this.isPrinting = true;
    this.logs = [];
    this.stderrLines = [];
    this.log(`Starting print job for file: ${path.basename(filePath)} (Copies: ${copiesNum})`);

    const scriptPath = path.join(this.resourcesPath, 'scripts', 'print-pipeline.sh');

    if (!fs.existsSync(scriptPath)) {
      this.isPrinting = false;
      return {
        success: false,
        error: `Print pipeline script missing at ${scriptPath}`,
      };
    }

    return new Promise((resolve) => {
      this.onProgress({
        status: 'STARTING',
        message: 'Initializing print job...',
        progress: 10,
      });

      const env = Object.assign({}, process.env, {
        PATH: `${path.join(this.resourcesPath, 'bin')}:${path.join(this.resourcesPath, 'scripts')}:${process.env.PATH || ''}`,
        DYLD_LIBRARY_PATH: `${path.join(this.resourcesPath, 'lib')}:${process.env.DYLD_LIBRARY_PATH || ''}`,
      });

      const child = spawn('zsh', [scriptPath, '--copies', copiesNum.toString(), filePath], {
        env,
        cwd: this.resourcesPath,
      });

      child.stdout.on('data', (data) => {
        const lines = data.toString().split('\n');
        for (const line of lines) {
          if (!line.trim()) continue;
          this.log(line);

          if (line.includes('[STEP 1/4]')) {
            this.onProgress({ status: 'FIRMWARE', message: 'Checking printer firmware...', progress: 25 });
          } else if (line.includes('[STEP 2/4]')) {
            this.onProgress({ status: 'GHOSTSCRIPT', message: 'Converting document to PostScript...', progress: 50 });
          } else if (line.includes('[STEP 3/4]')) {
            this.onProgress({ status: 'RASTERIZING', message: 'Rasterizing document for HP LaserJet 1020...', progress: 75 });
          } else if (line.includes('[STEP 4/4]')) {
            this.onProgress({ status: 'SENDING', message: 'Sending print job data over USB...', progress: 90 });
          }
        }
      });

      child.stderr.on('data', (data) => {
        const lines = data.toString().split('\n');
        for (const line of lines) {
          if (!line.trim()) continue;
          this.stderrLines.push(line);
          this.log(`[ERR] ${line}`);
        }
      });

      child.on('error', (err) => {
        this.isPrinting = false;
        this.log(`Process spawn error: ${err.message}`);
        this.onProgress({ status: 'FAILED', message: `Print failed: ${err.message}`, progress: 0 });
        resolve({ success: false, error: err.message, logs: this.logs });
      });

      child.on('close', (code) => {
        this.isPrinting = false;
        const fatalLines = this.stderrLines.filter((line) =>
          /^ERROR:/.test(line) ||
          /command not found|Not a pbm|Not a pbmraw|Not a pksmraw/.test(line)
        );
        // The foo2zjs wrapper exits 0 even when rasterizing fails.
        if (code === 0 && fatalLines.length === 0) {
          this.log('Print job successfully completed.');
          this.onProgress({ status: 'COMPLETED', message: 'Print job sent successfully!', progress: 100 });
          resolve({ success: true, logs: this.logs });
        } else {
          const errMsg = fatalLines.length
            ? fatalLines.join('\n')
            : `Print pipeline exited with code ${code}. Check logs for details.`;
          this.log(errMsg);
          this.onProgress({ status: 'FAILED', message: errMsg, progress: 0 });
          resolve({ success: false, error: errMsg, logs: this.logs });
        }
      });
    });
  }
}

module.exports = { PrintManager };
