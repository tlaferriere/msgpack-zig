local dap = require('dap')
dap.adapters.lldb = {
  type = 'executable',
  command = '/usr/bin/lldb', -- adjust as needed, must be absolute path
  name = 'lldb'
}

dap.configurations.zig = {
  {
    name = 'Launch',
    type = 'lldb',
    request = 'launch',
    program = '${workspaceFolder}/zig-out/bin/ut',
    cwd = '${workspaceFolder}',
    stopOnEntry = false,
    args = {},
  },
}

