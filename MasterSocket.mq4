// *********************************************************************
// Example of non-blocking server sockets, allowing connections
// from multiple concurrent clients. This example waits for 
// each \r-terminated line from a client (e.g. Telnet), and prints it 
// to the Experts log. The behaviour can be extended into something
// more realistic by changing Connection::ProcessIncomingMessage().
//
// Works on both MT4 and MT5 (32-bit and 64-bit). But see the 
// notes to socketselect3264() about the cheat which is used
// on 64-bit MT5.
// *********************************************************************

#property strict 


// ---------------------------------------------------------------------
// This code can either create an EA or a script. To create a script,
// comment out the line below. The code will then have OnTimer() 
// and OnTick() instead of OnStart()
// ---------------------------------------------------------------------

#define COMPILE_AS_EA


// ---------------------------------------------------------------------
// If we are compiling as a script, then we want the script
// to display the inputs page
// ---------------------------------------------------------------------

#ifndef COMPILE_AS_EA
#property show_inputs
#endif


// ---------------------------------------------------------------------
// User-configurable parameters
// ---------------------------------------------------------------------

// Purely cosmetic; causes MT4 to display the comments below
// as the options for the input, instead of using a boolean true/false
enum AllowedAddressesEnum {
   aaeLocal = 0,   // localhost only (127.0.0.1)
   aaeAny = 1      // All IP addresses
};

// User inputs
input int                     PortNumber = 51234;     // TCP/IP port number
input AllowedAddressesEnum    AcceptFrom = aaeLocal;  // Accept connections from


// ---------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------

// Size of temporary buffer used to read from client sockets
#define SOCKET_READ_BUFFER_SIZE  10000

// Defines the frequency of the main-loop processing, in milliseconds.
// This is either the duration of the sleep in OnStart(), if compiled
// as a script, or the frequency which is given to EventSetMillisecondTimer()
// if compiled as an EA. (In the context of an EA, the use of additional
// event-driven handling means that the timer is only a fallback, and
// this value could be set to a larger value, just acting as a sweep-up)
#define SLEEP_MILLISECONDS       10


// ---------------------------------------------------------------------
// Forward definitions of classes
// ---------------------------------------------------------------------

// Wrapper around a connected client socket
class Connection;

// ---------------------------------------------------------------------
// Winsock structure definitions and DLL imports
// ---------------------------------------------------------------------

/* WINSOCK 1.1 need this
struct sockaddr {
        ushort  sa_family;
        char    sa_data[14];
};

struct sockaddr_in {
        short   sin_family;
        u_short sin_port;
        struct  in_addr sin_addr;
        char    sin_zero[8];
};
*/

/* IN WINSOCK 2 just read The first 2 bytes in this block = sa_family
*/
struct sockaddr_in { //total 16 bytes used for bind() in param3
   short af_family;// 2 bytes, contain the address family that was used to create the socket, = 2 /* AF_INET 
   short port;// 2 bytes,(short)htons(PortNumber);//The htons function converts a u_short from host to TCP/IP network byte order (which is big-endian).*/
   int addr;//4 bytes, 0 /* INADDR_ANY */ or 0x100007F /* 127.0.0.1 */
   int dummy1;// 4 bytes
   int dummy2;// 4 bytes
};

struct timeval {
   int secs;
   int usecs;
};

struct fd_set {
   int count;
   int single_socket;
   int dummy[63];
};

struct fd_set64 {
   long count;
   long single_socket;
   long dummy[63];
};

#import "Ws2_32.dll"

   //The socket function creates a socket that is bound to a specific transport service provider.
   //https://msdn.microsoft.com/en-us/library/windows/desktop/ms740506(v=vs.85).aspx
   int socket(int, int, int);   
   // 2 =  AF_INET : The Internet Protocol version 4 (IPv4) address family.
   // 1 = SOCK_STREAM:A socket type that provides sequenced, reliable, two-way, connection-based byte streams with an OOB data transmission mechanism. This socket type uses the Transmission Control Protocol (TCP) for the Internet address family (AF_INET or AF_INET6).
   // 6 = IPPROTO_TCP:The Transmission Control Protocol (TCP). This is a possible value when the af parameter is AF_INET or AF_INET6 and the type parameter is SOCK_STREAM.
   
   
   //The bind function associates a local address with a socket. The bind function is required on an unconnected socket before subsequent calls to the listen function.
   //The bind function may also be used on an unconnected socket before subsequent calls to the connect, ConnectEx, WSAConnect, WSAConnectByList, or WSAConnectByName functions before send operations.
   int bind(int, sockaddr_in&, int);
   //s - A descriptor identifying an unbound socket. = returned value from socket() function
   //name - A pointer to a sockaddr structure of the local address to assign to the bound socket .
   //namelen - The length, in bytes, of the value pointed to by the name parameter.
   /*Return value
   If no error occurs, bind returns zero. Otherwise, it returns SOCKET_ERROR, and a specific error code can be retrieved by calling WSAGetLastError.*/
   
   
   
   
   
   //The htons function converts a u_short from host to TCP/IP network byte order (which is big-endian).
   int htons(int);
   
   //The listen function places a socket in a state in which it is listening for an incoming connection.
   //To accept connections, a socket is first created with the socket() function and bound to a local address with the bind() function. A backlog for incoming connections is specified with listen,and then the connections are accepted with the accept function. Sockets that are connection oriented, those of type SOCK_STREAM for example, are used with listen. 
   int listen(int, int);
   // first param = int return from socket()
   // second = The maximum length of the queue of pending connections.
   /*Return value
   If no error occurs, listen returns zero. Otherwise, a value of SOCKET_ERROR(-1) is returned, and a specific error code can be retrieved by calling WSAGetLastError.*/
   
   
   //The accept function permits an incoming connection attempt on a socket.
   int accept(int, int, int);
   //1st = int returned from socket()
   //2nd = pointer to keep client address value (same format with establish)
   //3rd = (2nd param'lenght) address length
   
   
   int closesocket(int);
   int select(int, fd_set&, int, int, timeval&);
   int select(int, fd_set64&, int, int, timeval&);  // See notes to socketselect3264() below
   int recv(int, uchar&[], int, int);
   int ioctlsocket(int, uint, uint&);
   int WSAGetLastError();
   int WSAAsyncSelect(int, int, uint, int);
#import   


// ---------------------------------------------------------------------
// Global variables
// ---------------------------------------------------------------------

// Flags whether OnInit was successful
bool SuccessfulInit = false;

// Handle of main listening server socket
int ServerSocket;

// List of currently connected clients
Connection * Clients[];

#ifdef COMPILE_AS_EA
// For EA compilation only, we track whether we have 
// successfully created a timer
bool CreatedTimer = false;   

// For EA compilation only, we track whether we have 
// done WSAAsyncSelect(), which can't reliably done in OnInit()
// because a chart handle isn't necessarily available
bool DoneAsyncSelect = false;
#endif

// ---------------------------------------------------------------------
// Initialisation - create listening socket
// ---------------------------------------------------------------------

void OnInit()
{
   SuccessfulInit = false;
   
   if (!TerminalInfoInteger(TERMINAL_DLLS_ALLOWED)) {Print("Requires \'Allow DLL imports\'");return;}
   
   // (Don't need to call WSAStartup because MT4 must have done this)

   // Create the main server socket
   ServerSocket = socket(2 /* AF_INET */, 1 /* SOCK_STREAM */, 6 /* IPPROTO_TCP */);
   if (ServerSocket == -1) {Print("ERROR " , WSAGetLastError() , " in socket creation");return;}
   
   // Put the socket into non-blocking mode
   uint nbmode = 1;
   if (ioctlsocket(ServerSocket, 0x8004667E /* FIONBIO */, nbmode) != 0) {Print("ERROR in setting non-blocking mode on server socket");return;}
   
   // Bind the socket to the specified port number. In this example,
   // we only accept connections from localhost
   sockaddr_in service;
   service.af_family = 2 /* AF_INET */;
   service.addr = (AcceptFrom == aaeAny ? 0 /* INADDR_ANY */ : 0x100007F /* 127.0.0.1 */);
   service.port = (short)htons(PortNumber);//The htons function converts a u_short from host to TCP/IP network byte order (which is big-endian).
   if (bind(ServerSocket, service, 16 /* sizeof(service) */) == -1) {Print("ERROR " , WSAGetLastError() , " in socket bind");return;}

   // Put the socket into listening mode
   if (listen(ServerSocket, 10) == -1) {Print("ERROR " , WSAGetLastError() , " in socket listen");return;}

   #ifdef COMPILE_AS_EA
   // If we're operating as an EA, set up event-driven handling of the sockets
   // as described below. (Also called from OnTick() because this requires a 
   // window handle, and the set-up will fail here if MT4 is starting up
   // with the EA already attached to a chart.)
   SetupAsyncSelect();
   #endif

   // Flag that we've successfully initialised
   SuccessfulInit = true;

   // If we're operating as an EA rather than a script, then try setting up a timer
   #ifdef COMPILE_AS_EA
   CreateTimer();
   #endif   
}


// ---------------------------------------------------------------------
// Variation between EA and script, depending on COMPILE_AS_EA above.
// The script version simply calls MainLoop() from a loop in OnStart().
// The EA version sets up a timer, and then calls MainLoop from OnTimer().
// It also has event-driven handling of socket activity by getting
// Windows to simulate keystrokes whenever a socket event happens.
// This is even faster than relying on the timer.
// ---------------------------------------------------------------------

#ifdef COMPILE_AS_EA
   // .........................................................
   // EA version. Simply calls MainLoop() from a timer.
   // The timer has previously been created in OnInit(), 
   // though we also check this in OnTick()...
   void OnTimer()
   {
      MainLoop();
   }
   
   // The function which creates the timer if it hasn't yet been set up
   void CreateTimer()
   {
      if (!CreatedTimer) CreatedTimer = EventSetMillisecondTimer(SLEEP_MILLISECONDS);//timer events will be fired at SLEEP_MILLISECONDS ms. --> call OnTimer()
   }

   // Timer creation can sometimes fail in OnInit(), at least
   // up until MT4 build 970, if MT4 is starting up with the EA already
   // attached to a chart. Therefore, as a fallback, we also 
   // handle OnTick(), and thus eventually set up the timer in
   // the EA's first tick if we failed to set it up in OnInit().
   // Similarly, the call to WSAAsyncSelect() may not be possible
   // in OnInit(), because it requires a chart handle, and that does
   // not exist in OnInit() during MT4 start-up.
   void OnTick()
   {
      CreateTimer();
      SetupAsyncSelect();
   }

   // In the context of an EA, we can improve the latency even further by making the 
   // processing event-driven, rather than just on a timer. If we use
   // WSAAsyncSelect() to tell Windows to send a WM_KEYDOWN whenever there's socket
   // activity, then this will fire the EA's OnChartEvent below. We can thus collect
   // socket events even faster than via the timed check, which becomes a back-up.
   // Note that WSAAsyncSelect() on a server socket also automatically applies 
   // to all client sockets created from it by accept(), and also that
   // WSAAsyncSelect() puts the socket into non-blocking mode, duplicating what
   // we have already above using ioctlsocket().
   // The further complication is that WSAAsyncSelect() requires a window handle,
   // and this is not available in OnInit() during MT4 start-up. Therefore,
   // like the timer though for different reasons, we repeat the call to
   // this function during OnTick()
   void SetupAsyncSelect()
   {
      if (DoneAsyncSelect) return;
      if (WSAAsyncSelect(ServerSocket, (int)ChartGetInteger(0, CHART_WINDOW_HANDLE), 0x100 /* WM_KEYDOWN */, 0xFF /* All events */) == 0) {
         DoneAsyncSelect = true;
      }
   }

   // In an EA, the use of WSAAsyncSelect() above means that Windows will fire a key-down 
   // message whenever there is socket activity. We can then respond to KEYDOWN events
   // in MQL4 as a way of knowing that there is socket activity to be dealt with.
   void OnChartEvent(const int id, const long& lparam, const double& dparam, const string& sparam)
   {
      if (id == CHARTEVENT_KEYDOWN) {
         // For a pseudo-keypress from WSAAsyncSelect(), the lparam will be the socket handle
         // (and the dparam will be the type of socket event, e.g. dparam = 1 = FD_READ).
         // Of course, this event can also be fired for real keypresses on the chart...
         
         // What is the lparam?
         if (lparam == ServerSocket) {
            // New pending connection on the listening server socket
            AcceptNewConnections();
         
         } else {
            // See if lparam is one of the client sockets, by looping 
            // through the Clients[] array
            int ctarr = ArraySize(Clients);
            for (int i = ctarr - 1; i >= 0; i--) {
               if (Clients[i].SocketHandle() == lparam) {

                  // Yes, we have found a socket matching this "keyboard" event.
                  // Return value from ReadAnyPendingData() is true
                  // if the socket still seems to be alive; false if 
                  // the connection seems to have been closed, and should be discarded
                  if (Clients[i].ReadAnyPendingData()) {
                     // Socket still seems to be alive
                     
                  } else {
                     // Socket appears to be dead
                     ReleaseClientSocket(i, ctarr);
                  }
                  return; //Early exit!
               }
            }
            
            // If we get here, then the lparam does not match any
            // of the sockets, and the event must be a real keypress,
            // not a pseudo-keypress from WSAAsyncSelect()
         }
      }
   }
    
#else

   // .........................................................
   // Script version. Simply calls MainLoop() repeatedly
   // until the script is removed, with a small sleep between calls
   void OnStart()
   {
      while (!IsStopped()) {
         MainLoop();
         Sleep(SLEEP_MILLISECONDS);
      }
   }
#endif


// ---------------------------------------------------------------------
// Main processing loop which handles new incoming connections, and reads
// data from existing connections.
// Can either be called from OnTimer() in an EA; or from OnStart() in a script, 
// on a continuous loop until IsStopped() is true. In an EA, socket 
// activity should almost always get handled by the event-driven stuff 
// above, and this timer loop is just a fallback.
// ---------------------------------------------------------------------

void MainLoop()//also called by timer, to accept new connection and read msg
{
   // Do nothing if init was unsuccessful
   if (!SuccessfulInit) return;

   // This main timer loop does two things: accepts new incoming 
   // connections, and reads pending data on all sockets (including
   // new ones which have just been accepted)
   AcceptNewConnections();
   ReadSocketMessages();   
}

// Accept any new pending connections on the main listening server socket,
// wrapping the new caller in a Connection object and putting it
// into the Clients[] array
void AcceptNewConnections()
{
   int selres = socketselect3264(ServerSocket);
   if (selres > 0) {
   
      Print("New incoming connection...");
      int NewClientSocket = accept(ServerSocket, 0, 0);
      if (NewClientSocket == -1) {
         if (WSAGetLastError() == 10035 /* WSAEWOULDBLOCK */) {
            // Blocking warning; ignore
            Print("... would block; ignore");
         } else {
            Print("ERROR " , WSAGetLastError() , " in socket accept");
         }

      } else {
         Print("...accepted");
         
         // Create a new Connection object to wrap the client socket,
         // and add it to the Clients[] array
         int ctarr = ArraySize(Clients);
         ArrayResize(Clients, ctarr + 1);
         Clients[ctarr] = new Connection(NewClientSocket);               
         Print("Got connection to client #", Clients[ctarr].GetID());
      }
   }
}


// Process any incoming data from all client connections
// (including any which have just been accepted, above)
void ReadSocketMessages()
{
   int ctarr = ArraySize(Clients);
   for (int i = ctarr - 1; i >= 0; i--) {
      // Return value from ReadAnyPendingData() is true
      // if the socket still seems to be alive; false if 
      // the connection seems to have been closed, and should be discarded
      if (Clients[i].ReadAnyPendingData()) {
         // Socket still seems to be alive
         
      } else {
         // Socket appears to be dead. Delete, and remove from list
         ReleaseClientSocket(i, ctarr);
      }
   }
}

// Discards a client socket which appears to have died, deleting the Connection class
// and removing it from the Clients[] array. Takes two parameters: the index of 
// the connection within the Clients[] array, and the current size of that array (which
// is passed by reference, with the function sending back the decremented size)
void ReleaseClientSocket(int idxReleaseAt, int & SizeOfArray)
{
   Print("Lost connection to client #", Clients[idxReleaseAt].GetID());
   
   delete Clients[idxReleaseAt];
   for (int j = idxReleaseAt + 1; j < SizeOfArray; j++) {
      Clients[j - 1] = Clients[j];
   }
   SizeOfArray--;
   ArrayResize(Clients, SizeOfArray);           
}

// Wraps the Winsock select() function, doing an immediate non-blocking
// check of a single socket. This is the one area where we must
// vary things between 32-bit and 64-bit. On 64-bit MT5, we can get away
// with using Winsock calls where everything is defined as a 32-bit int;
// we can rely on the fact that socket and window handles are only ever going
// to be 4 bytes rather than 8 bytes - naughty, but works in practice.
// The one exception is the fd_set structure. On 64-bit MT5, 
// we must pass a version of the fd_set where everything is defined
// as 8-byte long rather than 4-byte int. Note that this applies to
// the MT5 version, not the O/S. On 32-bit MT5, even on a 64-bit computer,
// we use the same structure as MT4: 4-byte int rather than 8-byte long
int socketselect3264(int TestSocket)
{
   timeval waitfor;
   waitfor.secs = 0;
   waitfor.usecs = 0;

   // The following, incidentally, is permitted on MT4, but obviously returns false...
   if (TerminalInfoInteger(TERMINAL_X64)) {
      fd_set64 PollSocket64;
      PollSocket64.count = 1;
      PollSocket64.single_socket = TestSocket;

      return select(0, PollSocket64, 0, 0, waitfor);

   } else {
      fd_set PollSocket32;
      PollSocket32.count = 1;
      PollSocket32.single_socket = TestSocket;
   
      return select(0, PollSocket32, 0, 0, waitfor);
   }
}


// ---------------------------------------------------------------------
// Termination - clean up sockets
// ---------------------------------------------------------------------

void OnDeinit(const int reason)
{
   closesocket(ServerSocket);
   
   for (int i = 0; i < ArraySize(Clients); i++) {
      delete Clients[i];
   }
   ArrayResize(Clients, 0);
   
   #ifdef COMPILE_AS_EA
   EventKillTimer();
   CreatedTimer = false;
   DoneAsyncSelect = false;
   #endif
}


// ---------------------------------------------------------------------
// Simple wrapper around each connected client socket
// ---------------------------------------------------------------------

class Connection {
private:
   // Client socket handle
   int mSocket;

   // Temporary buffer used to handle incoming data
   uchar mTempBuffer[SOCKET_READ_BUFFER_SIZE];
   
   // Stored-up data, waiting for a \r character 
   string mPendingData;
   
public:
   Connection(int ClientSocket);
   ~Connection();
   string GetID() {return IntegerToString(mSocket);}
   int SocketHandle() {return mSocket;}
      
   bool ReadAnyPendingData();
   void ProcessIncomingMessage(string strMessage);
};

// Constructor, called with the handle of a newly accepted socket
Connection::Connection(int ClientSocket)
{
   mPendingData = "";
   mSocket = ClientSocket; 
   
   // Put the client socket into non-blocking mode
   uint nbmode = 1;
   if (ioctlsocket(mSocket, 0x8004667E /* FIONBIO */, nbmode) != 0) {Print("ERROR in setting non-blocking mode on client socket");}
}

// Destructor. Simply close the client socket
Connection::~Connection()
{
   closesocket(mSocket);
}

// Called repeatedly on a timer, to check whether any
// data is available on this client connection. Returns true if the 
// client still seems to be connected (*not* if there's new data); 
// returns false if the connection seems to be dead. 
bool Connection::ReadAnyPendingData()
{
   // Check the client socket for data-readability
   int selres = socketselect3264(mSocket);
   if (selres > 0) {
      
      // Winsock says that there is data waiting to be read on this socket
      int szData = recv(mSocket, mTempBuffer, SOCKET_READ_BUFFER_SIZE, 0);
      if (szData > 0) {
         // Convert the buffer to a string, and add it to any pending
         // data which we already have on this connection
         string strIncoming = CharArrayToString(mTempBuffer, 0, szData);
         mPendingData += strIncoming;
         
         // Do we have a complete message (or more than one) ending in \r?
         int idxTerm = StringFind(mPendingData, "\r");
         while (idxTerm >= 0) {
            if (idxTerm > 0) {
               string strMsg = StringSubstr(mPendingData, 0, idxTerm);         
               
               // Strip out any \n characters lingering from \r\n combos
               StringReplace(strMsg, "\n", "");
               
               // Print the \r-terminated message in the log
               ProcessIncomingMessage(strMsg);
            }               
         
            // Keep looping until we have extracted all the \r delimited 
            // messages, and leave any residue in the pending data 
            mPendingData = StringSubstr(mPendingData, idxTerm + 1);
            idxTerm = StringFind(mPendingData, "\r");
         }
         
         return true;
      
      } else if (WSAGetLastError() == 10035 /* WSAEWOULDBLOCK */) {
         // Would block; not an error
         return true;
         
      } else {
         // recv() failed. Assume socket is dead
         return false;
      }
   
   } else if (selres == -1) {
      // Assume socket is dead
      return false;
      
   } else {
      // No pending data
      return true;
   }
}

// Can override this with whatever you want to do with incoming messages:
// handling trading commands, send data back down the socket etc etc etc
void Connection::ProcessIncomingMessage(string strMessage)
{
   Print("#" , GetID() , ": " , strMessage);
}