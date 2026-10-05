document.addEventListener('DOMContentLoaded', () => {
  // DOM Elements - Navigation & Badge
  const tabBtns = document.querySelectorAll('.tab-btn');
  const tabPanels = document.querySelectorAll('.tab-panel');
  const statusBadge = document.getElementById('statusBadge');
  const statusBadgeText = document.getElementById('statusBadgeText');

  // DOM Elements - Setup Tab
  const setupProgressMsg = document.getElementById('setupProgressMsg');
  const setupProgressPct = document.getElementById('setupProgressPct');
  const setupProgressBar = document.getElementById('setupProgressBar');
  const btnStartSetup = document.getElementById('btnStartSetup');
  const btnViewLogs = document.getElementById('btnViewLogs');
  const errorCard = document.getElementById('errorCard');
  const errorTitle = document.getElementById('errorTitle');
  const errorMessage = document.getElementById('errorMessage');
  const errorStepsList = document.getElementById('errorStepsList');

  // Checklist Step Elements
  const stepMacos = document.getElementById('step-macos');
  const stepUsb = document.getElementById('step-usb');
  const stepBinaries = document.getElementById('step-binaries');
  const stepFirmware = document.getElementById('step-firmware');

  // DOM Elements - Print Tab
  const dropZone = document.getElementById('dropZone');
  const btnBrowseFile = document.getElementById('btnBrowseFile');
  const fileCard = document.getElementById('fileCard');
  const fileNameDisplay = document.getElementById('fileName');
  const filePathDisplay = document.getElementById('filePath');
  const btnRemoveFile = document.getElementById('btnRemoveFile');
  const copiesCountInput = document.getElementById('copiesCount');
  const btnMinusCopy = document.getElementById('btnMinusCopy');
  const btnPlusCopy = document.getElementById('btnPlusCopy');
  const btnPrint = document.getElementById('btnPrint');
  const printStatusBox = document.getElementById('printStatusBox');
  const printStatusText = document.getElementById('printStatusText');
  const printErrorCard = document.getElementById('printErrorCard');
  const printErrorMessage = document.getElementById('printErrorMessage');

  // DOM Elements - Logs Tab
  const logsOutput = document.getElementById('logsOutput');
  const btnCopyLogs = document.getElementById('btnCopyLogs');

  // App State
  let selectedFilePath = null;
  let currentPrinterState = 'NOT_STARTED';

  // ----------------------------------------------------
  // 1. Navigation / Tab Switching
  // ----------------------------------------------------
  tabBtns.forEach(btn => {
    btn.addEventListener('click', () => {
      const targetTab = btn.getAttribute('data-tab');
      tabBtns.forEach(b => b.classList.remove('active'));
      tabPanels.forEach(p => p.classList.remove('active'));

      btn.classList.add('active');
      document.getElementById(`tab-${targetTab}`).classList.add('active');

      if (targetTab === 'logs') {
        refreshLogs();
      }
    });
  });

  btnViewLogs.addEventListener('click', () => {
    document.querySelector('[data-tab="logs"]').click();
  });

  // ----------------------------------------------------
  // 2. Status Badge Update Helper
  // ----------------------------------------------------
  function setStatusBadge(type, text) {
    statusBadge.className = `status-badge status-${type}`;
    statusBadgeText.textContent = text;
  }

  // ----------------------------------------------------
  // 3. Setup Progress & State Machine Renderer
  // ----------------------------------------------------
  function resetChecklist() {
    [stepMacos, stepUsb, stepBinaries, stepFirmware].forEach(item => {
      item.className = 'checklist-item';
      item.querySelector('.item-icon').textContent = '●';
    });
  }

  function setStepStatus(stepEl, status) {
    stepEl.className = `checklist-item ${status}`;
    const icon = stepEl.querySelector('.item-icon');
    if (status === 'done') icon.textContent = '✓';
    else if (status === 'failed') icon.textContent = '✕';
    else if (status === 'active') icon.textContent = '⏳';
  }

  window.electronAPI.onSetupProgress((data) => {
    const { state, message, progress, errorInfo, logs } = data;
    currentPrinterState = state;

    setupProgressMsg.textContent = message;
    setupProgressPct.textContent = `${progress}%`;
    setupProgressBar.style.width = `${progress}%`;

    if (logs) {
      logsOutput.textContent = logs.join('\n');
    }

    if (state === 'CHECKING') {
      setStatusBadge('checking', 'Checking...');
      setStepStatus(stepMacos, 'done');
      setStepStatus(stepUsb, 'active');
      errorCard.classList.add('hidden');
    } else if (state === 'INSTALLING') {
      setStatusBadge('checking', 'Installing...');
      setStepStatus(stepMacos, 'done');
      setStepStatus(stepUsb, 'done');
      setStepStatus(stepBinaries, 'active');
    } else if (state === 'CONFIGURING') {
      setStatusBadge('checking', 'Configuring...');
      setStepStatus(stepMacos, 'done');
      setStepStatus(stepUsb, 'done');
      setStepStatus(stepBinaries, 'done');
      setStepStatus(stepFirmware, 'active');
    } else if (state === 'READY') {
      setStatusBadge('ready', 'Printer Ready');
      setStepStatus(stepMacos, 'done');
      setStepStatus(stepUsb, 'done');
      setStepStatus(stepBinaries, 'done');
      setStepStatus(stepFirmware, 'done');
      errorCard.classList.add('hidden');
      btnStartSetup.textContent = 'Re-Run Setup';
    } else if (state === 'FAILED') {
      setStatusBadge('failed', 'Setup Failed');
      setStepStatus(stepMacos, 'done');
      setStepStatus(stepUsb, 'failed');
      btnStartSetup.textContent = 'Try Again';

      // Render Actionable Error View
      if (errorInfo) {
        errorTitle.textContent = errorInfo.title || 'Setup Error';
        errorMessage.textContent = errorInfo.message || 'An error occurred during setup.';
        
        errorStepsList.innerHTML = '';
        const steps = errorInfo.actionableSteps || ['1. Ensure printer is connected.', '2. Click Try Again.'];
        steps.forEach(stepText => {
          const li = document.createElement('li');
          li.textContent = stepText;
          errorStepsList.appendChild(li);
        });
        errorCard.classList.remove('hidden');
        errorCard.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
      }
    }
  });

  btnStartSetup.addEventListener('click', async () => {
    errorCard.classList.add('hidden');
    btnStartSetup.disabled = true;
    resetChecklist();
    await window.electronAPI.startSetup();
    btnStartSetup.disabled = false;
  });

  // ----------------------------------------------------
  // 4. File Selection & Drag-and-Drop
  // ----------------------------------------------------
  function setSelectedFile(filePath) {
    if (!filePath) return;
    selectedFilePath = filePath;
    fileNameDisplay.textContent = filePath.split('/').pop();
    filePathDisplay.textContent = filePath;
    
    fileCard.classList.remove('hidden');
    dropZone.classList.add('hidden');
    btnPrint.disabled = false;
  }

  function clearSelectedFile() {
    selectedFilePath = null;
    fileCard.classList.add('hidden');
    dropZone.classList.remove('hidden');
    btnPrint.disabled = true;
  }

  btnBrowseFile.addEventListener('click', async () => {
    const file = await window.electronAPI.selectFile();
    if (file) setSelectedFile(file);
  });

  dropZone.addEventListener('click', async (e) => {
    if (e.target !== btnBrowseFile) {
      const file = await window.electronAPI.selectFile();
      if (file) setSelectedFile(file);
    }
  });

  dropZone.addEventListener('dragover', (e) => {
    e.preventDefault();
    dropZone.classList.add('drag-over');
  });

  dropZone.addEventListener('dragleave', () => {
    dropZone.classList.remove('drag-over');
  });

  dropZone.addEventListener('drop', (e) => {
    e.preventDefault();
    dropZone.classList.remove('drag-over');

    if (e.dataTransfer.files && e.dataTransfer.files.length > 0) {
      const file = e.dataTransfer.files[0];
      const ext = file.name.split('.').pop().toLowerCase();
      if (ext === 'pdf' || ext === 'ps') {
        setSelectedFile(file.path);
      } else {
        alert('Please select a valid PDF or PostScript (.ps) document.');
      }
    }
  });

  btnRemoveFile.addEventListener('click', clearSelectedFile);

  // ----------------------------------------------------
  // 5. Copies Counter
  // ----------------------------------------------------
  btnMinusCopy.addEventListener('click', () => {
    let val = parseInt(copiesCountInput.value, 10) || 1;
    if (val > 1) copiesCountInput.value = val - 1;
  });

  btnPlusCopy.addEventListener('click', () => {
    let val = parseInt(copiesCountInput.value, 10) || 1;
    if (val < 99) copiesCountInput.value = val + 1;
  });

  copiesCountInput.addEventListener('change', () => {
    let val = parseInt(copiesCountInput.value, 10);
    if (isNaN(val) || val < 1) copiesCountInput.value = 1;
    if (val > 99) copiesCountInput.value = 99;
  });

  // ----------------------------------------------------
  // 6. Print Execution
  // ----------------------------------------------------
  function hidePrintError() {
    printErrorCard.classList.add('hidden');
    printErrorMessage.textContent = '';
    printStatusBox.classList.remove('is-error');
  }

  window.electronAPI.onPrintProgress((data) => {
    const { status, message } = data;
    printStatusBox.classList.remove('hidden');
    printStatusText.textContent = message;

    if (status === 'COMPLETED') {
      hidePrintError();
      setTimeout(() => {
        printStatusBox.classList.add('hidden');
        alert('Print job sent successfully to HP LaserJet 1020!');
      }, 1000);
    } else if (status === 'FAILED') {
      printStatusBox.classList.add('is-error');
      printStatusText.textContent = 'Print failed. The document was not sent.';
      printErrorMessage.textContent = message;
      printErrorCard.classList.remove('hidden');
      printErrorCard.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
    } else {
      hidePrintError();
    }
  });

  btnPrint.addEventListener('click', async () => {
    if (!selectedFilePath) return;

    btnPrint.disabled = true;
    hidePrintError();
    printStatusBox.classList.remove('hidden');
    printStatusText.textContent = 'Initiating print process...';

    const copies = parseInt(copiesCountInput.value, 10) || 1;
    const result = await window.electronAPI.printFile(selectedFilePath, copies);

    btnPrint.disabled = false;
    if (!result.success) {
      printStatusBox.classList.add('is-error');
      printErrorMessage.textContent = result.error;
      printErrorCard.classList.remove('hidden');
    }
  });

  // ----------------------------------------------------
  // 7. Logs Refresh & Copy
  // ----------------------------------------------------
  async function refreshLogs() {
    const { installLogs, printLogs } = await window.electronAPI.getLogs();
    const allLogs = [...installLogs, '--- Print Logs ---', ...printLogs];
    logsOutput.textContent = allLogs.length > 1 ? allLogs.join('\n') : 'No logs generated yet.';
  }

  btnCopyLogs.addEventListener('click', () => {
    navigator.clipboard.writeText(logsOutput.textContent);
    btnCopyLogs.textContent = 'Copied!';
    setTimeout(() => {
      btnCopyLogs.textContent = 'Copy Logs';
    }, 2000);
  });

  // ----------------------------------------------------
  // 8. Startup Check
  // ----------------------------------------------------
  async function init() {
    setStatusBadge('checking', 'Checking Status...');
    const status = await window.electronAPI.getPrinterStatus();
    
    // Auto-run initial setup check on app launch
    await window.electronAPI.startSetup();
  }

  init();
});
