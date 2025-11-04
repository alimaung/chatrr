# Terminal Chat Implementation Plan
## TCP Socket Chat for Windows PCs (PowerShell)

---

## 1. PROJECT OVERVIEW

### 1.1 Objective
Create a simple bidirectional terminal chat application that allows two Windows PCs on the same local network to exchange messages in real-time using TCP sockets.

### 1.2 Technology Stack
- **Language**: PowerShell 5.1+ (.ps1 scripts)
- **Protocol**: TCP/IP
- **Platform**: Windows 10/11
- **Dependencies**: Native .NET classes (no external modules required)

### 1.3 Core Requirements
- One PC acts as server (listener)
- One PC acts as client (connector)
- Real-time bidirectional messaging
- Simple terminal interface
- Graceful connection handling
- Network error handling

---

## 2. ARCHITECTURE DESIGN

### 2.1 System Architecture
```
┌─────────────────┐         TCP Socket          ┌─────────────────┐
│   PC 1 (Server) │ ◄─────────────────────────► │   PC 2 (Client) │
│                 │         Port: 12345          │                 │
│  ┌───────────┐  │                              │  ┌───────────┐  │
│  │  Listener │  │                              │  │  Connector│  │
│  └─────┬─────┘  │                              │  └─────┬─────┘  │
│        │        │                              │        │        │
│  ┌─────▼─────┐  │                              │  ┌─────▼─────┐  │
│  │ Input     │  │                              │  │ Input     │  │
│  │ Handler   │  │                              │  │ Handler   │  │
│  └─────┬─────┘  │                              │  └─────┬─────┘  │
│        │        │                              │        │        │
│  ┌─────▼─────┐  │                              │  ┌─────▼─────┐  │
│  │ Output    │  │                              │  │ Output    │  │
│  │ Display   │  │                              │  │ Display   │  │
│  └───────────┘  │                              │  └───────────┘  │
└─────────────────┘                              └─────────────────┘
```

### 2.2 Component Breakdown

#### 2.2.1 Server Components
- **Connection Listener**: Accepts incoming connections
- **Connection Handler**: Manages connected client
- **Input Thread**: Reads from keyboard/stdin
- **Receive Thread**: Reads from network stream
- **Output Handler**: Displays messages to terminal
- **Shutdown Handler**: Graceful connection closure

#### 2.2.2 Client Components
- **Connection Initiator**: Establishes connection to server
- **Input Thread**: Reads from keyboard/stdin
- **Receive Thread**: Reads from network stream
- **Output Handler**: Displays messages to terminal
- **Shutdown Handler**: Graceful disconnection

---

## 3. TECHNICAL SPECIFICATIONS

### 3.1 Network Configuration
- **Protocol**: TCP (reliable, ordered delivery)
- **Default Port**: 12345 (configurable)
- **Binding Address**: 0.0.0.0 (all network interfaces)
- **Connection Type**: Persistent (keep-alive until disconnect)
- **Encoding**: UTF-8 (Unicode support)

### 3.2 Message Format
- **Type**: Plain text strings
- **Delimiter**: Newline character (`\n` or `\r\n`)
- **Max Length**: 4096 characters per message (configurable)
- **Special Commands**: 
  - `/quit` or `/exit` - Close connection gracefully
  - `/help` - Show available commands

### 3.3 Threading Model
- **Main Thread**: Network connection management
- **Input Thread**: Non-blocking keyboard input reading
- **Receive Thread**: Non-blocking network stream reading
- **Synchronization**: Thread-safe message queues or direct console writes

---

## 4. FILE STRUCTURE

```
chatrr/
├── server.ps1          # Server-side script
├── client.ps1          # Client-side script
├── common.ps1          # Shared functions/utilities
├── README.md           # User documentation
└── IMPLEMENTATION_PLAN.md  # This file
```

### 4.1 File Responsibilities

#### `server.ps1`
- Server initialization and configuration
- TCP listener setup and connection acceptance
- Server-side message handling
- Server shutdown logic

#### `client.ps1`
- Client initialization and configuration
- TCP client connection establishment
- Client-side message handling
- Client disconnect logic

#### `common.ps1` (Optional)
- Shared utility functions
- Network helper functions
- Configuration constants
- Common error handling

---

## 5. IMPLEMENTATION STEPS

### Phase 1: Core Infrastructure (Foundation)

#### Step 1.1: Network Setup
- [ ] Create TCP listener function (server)
- [ ] Create TCP client connector function (client)
- [ ] Implement IP address discovery helper
- [ ] Implement port configuration
- [ ] Add connection timeout handling

#### Step 1.2: Message I/O
- [ ] Implement network stream reader (async)
- [ ] Implement network stream writer
- [ ] Implement console input reader (non-blocking)
- [ ] Implement console output writer (thread-safe)
- [ ] Handle message encoding/decoding (UTF-8)

### Phase 2: User Interface

#### Step 2.1: Terminal UI
- [ ] Design message display format
- [ ] Implement input prompt
- [ ] Add connection status indicators
- [ ] Implement clear screen on connect
- [ ] Add visual separators for sent/received messages

#### Step 2.2: User Experience
- [ ] Display server IP/port on startup (server)
- [ ] Prompt for server IP/port (client)
- [ ] Show connection success/failure messages
- [ ] Display disconnect messages
- [ ] Add welcome/help text

### Phase 3: Concurrency & Threading

#### Step 3.1: Input Handling
- [ ] Implement background job for keyboard input
- [ ] Implement background job for network receive
- [ ] Handle thread synchronization
- [ ] Prevent input/output race conditions

#### Step 3.2: Event Handling
- [ ] Implement Ctrl+C handler (graceful shutdown)
- [ ] Handle connection loss detection
- [ ] Handle network errors gracefully
- [ ] Implement reconnection logic (optional)

### Phase 4: Error Handling & Edge Cases

#### Step 4.1: Network Errors
- [ ] Handle connection refused errors
- [ ] Handle timeout errors
- [ ] Handle network unreachable errors
- [ ] Handle port already in use errors
- [ ] Handle connection reset errors

#### Step 4.2: Input Validation
- [ ] Validate IP address format
- [ ] Validate port number range
- [ ] Handle empty messages
- [ ] Handle very long messages
- [ ] Sanitize special characters if needed

### Phase 5: Polish & Testing

#### Step 5.1: Code Quality
- [ ] Add error logging
- [ ] Add debug mode (optional)
- [ ] Code comments and documentation
- [ ] Function modularization

#### Step 5.2: Testing
- [ ] Test on same PC (localhost)
- [ ] Test on two different PCs
- [ ] Test connection failures
- [ ] Test message delivery
- [ ] Test graceful shutdown
- [ ] Test special characters and Unicode

---

## 6. DETAILED FUNCTION SPECIFICATIONS

### 6.1 Server Functions

#### `Start-Server`
- **Purpose**: Initialize and start TCP listener
- **Parameters**: 
  - `Port` (int, default: 12345)
  - `IPAddress` (string, default: "0.0.0.0")
- **Returns**: TcpListener object
- **Side Effects**: Binds to port, starts listening

#### `Accept-Client`
- **Purpose**: Accept incoming client connection
- **Parameters**: TcpListener object
- **Returns**: TcpClient object
- **Side Effects**: Blocks until client connects

#### `Receive-Message`
- **Purpose**: Read message from network stream
- **Parameters**: NetworkStream object
- **Returns**: String message or null on disconnect
- **Side Effects**: Blocks until message received or disconnect

#### `Send-Message`
- **Purpose**: Write message to network stream
- **Parameters**: NetworkStream object, String message
- **Returns**: Boolean (success/failure)
- **Side Effects**: Sends data over network

#### `Get-LocalIP`
- **Purpose**: Get local IP address for display
- **Parameters**: None
- **Returns**: String IP address
- **Side Effects**: None

### 6.2 Client Functions

#### `Connect-ToServer`
- **Purpose**: Establish connection to server
- **Parameters**: 
  - `ServerIP` (string)
  - `Port` (int, default: 12345)
- **Returns**: TcpClient object or null on failure
- **Side Effects**: Attempts TCP connection

#### `Receive-Message` (same as server)
- **Purpose**: Read message from network stream
- **Parameters**: NetworkStream object
- **Returns**: String message or null on disconnect

#### `Send-Message` (same as server)
- **Purpose**: Write message to network stream
- **Parameters**: NetworkStream object, String message
- **Returns**: Boolean (success/failure)

### 6.3 Common Functions

#### `Read-ConsoleInput`
- **Purpose**: Non-blocking console input reader
- **Parameters**: None
- **Returns**: String or null if no input
- **Side Effects**: Reads from stdin

#### `Write-Message`
- **Purpose**: Thread-safe message display
- **Parameters**: String message, String type ("sent"/"received")
- **Returns**: None
- **Side Effects**: Writes to console

#### `Handle-Disconnect`
- **Purpose**: Clean up on disconnect
- **Parameters**: NetworkStream, TcpClient
- **Returns**: None
- **Side Effects**: Closes streams and connections

---

## 7. ERROR HANDLING STRATEGY

### 7.1 Connection Errors
- **Port in use**: Display error, suggest different port
- **Connection refused**: Client error - server not running or wrong IP
- **Timeout**: Display timeout message, allow retry
- **Network unreachable**: Check IP address and network connectivity

### 7.2 Runtime Errors
- **Stream read errors**: Detect disconnect, cleanup gracefully
- **Stream write errors**: Retry once, then disconnect
- **Keyboard interrupt (Ctrl+C)**: Send disconnect message, cleanup

### 7.3 Error Messages
- User-friendly error messages
- Include suggestions for resolution
- Log technical details (optional debug mode)

---

## 8. USER WORKFLOW

### 8.1 Server Startup Flow
1. User runs `.\server.ps1`
2. Script displays local IP address(es)
3. Script displays listening port
4. Script waits for client connection
5. On connection: Clear screen, show "Connected!" message
6. Enter chat mode (bidirectional messaging)

### 8.2 Client Startup Flow
1. User runs `.\client.ps1`
2. Script prompts for server IP address
3. Script prompts for port (or uses default)
4. Script attempts connection
5. On success: Clear screen, show "Connected!" message
6. Enter chat mode (bidirectional messaging)

### 8.3 Chat Mode Flow
1. Display prompt for input (e.g., "You: ")
2. User types message and presses Enter
3. Message sent over network
4. Display "You: [message]" locally
5. Continuously listen for incoming messages
6. Display "Them: [message]" when received
7. Repeat until disconnect

### 8.4 Disconnect Flow
1. User types `/quit` or `/exit`
2. Send disconnect message to peer
3. Close network streams
4. Close TCP connection
5. Display "Disconnected" message
6. Exit script

---

## 9. SECURITY CONSIDERATIONS

### 9.1 Current Scope (Local Network Only)
- No authentication required
- No encryption (plain text)
- Trust all connections on port
- Suitable only for trusted local networks

### 9.2 Future Enhancements (Not in MVP)
- TLS/SSL encryption
- Authentication tokens
- Message encryption
- Firewall considerations
- Port access control

---

## 10. TESTING STRATEGY

### 10.1 Unit Testing (Manual)
- Test each function independently
- Test error cases
- Test edge cases (empty messages, long messages)

### 10.2 Integration Testing
- Test server startup
- Test client connection
- Test bidirectional messaging
- Test disconnect scenarios

### 10.3 Network Testing
- Test on localhost (same PC)
- Test on same network (two PCs)
- Test with firewall enabled/disabled
- Test connection failures
- Test message delivery reliability

### 10.4 Edge Case Testing
- Very long messages (>1000 chars)
- Special characters (Unicode, emoji)
- Rapid message sending
- Connection interruption mid-message
- Multiple connection attempts

---

## 11. CONFIGURATION OPTIONS

### 11.1 Configurable Parameters
- **Port**: Default 12345, configurable via parameter
- **Encoding**: UTF-8 (hardcoded for MVP)
- **Buffer Size**: 4096 bytes (configurable)
- **Timeout**: 30 seconds (configurable)
- **Message Format**: Simple text (extensible)

### 11.2 Command-Line Arguments
- Server: `.\server.ps1 [-Port <int>]`
- Client: `.\client.ps1 [-ServerIP <string>] [-Port <int>]`

---

## 12. DEPLOYMENT

### 12.1 File Distribution
- Copy `server.ps1` to PC 1
- Copy `client.ps1` to PC 2
- Ensure PowerShell execution policy allows script execution

### 12.2 Execution Policy
- User may need to run: `Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser`
- Or run scripts with: `powershell -ExecutionPolicy Bypass -File .\server.ps1`

### 12.3 Network Requirements
- Both PCs on same local network
- Firewall may need to allow TCP port 12345
- PCs must be able to ping each other

---

## 13. FUTURE ENHANCEMENTS (Post-MVP)

### 13.1 Features
- Multiple clients (chat room)
- Username/identity system
- Message history/logging
- File transfer capability
- Encrypted communication
- GUI version
- Cross-platform support

### 13.2 Improvements
- Better error recovery
- Auto-reconnection
- Connection status indicators
- Typing indicators
- Message timestamps
- Colored output

---

## 14. IMPLEMENTATION ORDER

### Recommended Sequence:
1. **Basic TCP Connection** (server listens, client connects)
2. **One-Way Messaging** (client sends, server receives)
3. **Bidirectional Messaging** (both can send/receive)
4. **Concurrent I/O** (handle input and receive simultaneously)
5. **Error Handling** (connection errors, disconnects)
6. **UI Polish** (formatted output, prompts, status)
7. **Edge Cases** (long messages, special chars, graceful shutdown)
8. **Testing** (local and network testing)

---

## 15. SUCCESS CRITERIA

### MVP Must Have:
- ✅ Server can accept one client connection
- ✅ Client can connect to server
- ✅ Both can send messages
- ✅ Both can receive messages
- ✅ Messages display correctly
- ✅ Graceful disconnect works
- ✅ Basic error handling

### Nice to Have:
- ⭐ Username display
- ⭐ Timestamps
- ⭐ Colored output
- ⭐ Help command
- ⭐ Connection status

---

## 16. KNOWN LIMITATIONS

### Technical Limitations:
- Single client per server (no chat rooms)
- No message persistence (lost on disconnect)
- No encryption (plain text only)
- Windows PowerShell only (not cross-platform)
- Requires manual IP address entry

### Network Limitations:
- Local network only
- Firewall configuration may be needed
- Router/NAT may block connections (usually not on local network)

---

## END OF IMPLEMENTATION PLAN

