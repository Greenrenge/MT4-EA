//+------------------------------------------------------------------+
//|                                                           tt.mqh |
//|                                                       Sorasak S. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Sorasak S."
#property link      "https://www.mql5.com"
#property strict
//+------------------------------------------------------------------+
//| defines                                                          |
//+------------------------------------------------------------------+
// #define MacrosHello   "Hello, world!"
// #define MacrosYear    2010
//+------------------------------------------------------------------+
//| DLL imports                                                      |
//+------------------------------------------------------------------+
// #import "user32.dll"
//   int      SendMessageA(int hWnd,int Msg,int wParam,int lParam);
// #import "my_expert.dll"
//   int      ExpertRecalculate(int wParam,int lParam);
// #import
//+------------------------------------------------------------------+
//| EX5 imports                                                      |
//+------------------------------------------------------------------+
// #import "stdlib.ex5"
//   string ErrorDescription(int error_code);
// #import
//+------------------------------------------------------------------+






// ---------------------------------------------------------------------
// User-configurable parameters
// ---------------------------------------------------------------------
 
// Purely cosmetic; causes MT4 to display the comments below
// as the options for the input, instead of using a boolean true/false
enum AllowedAddressesEnum {
   LOCALTHOST = 0,   // localhost only (127.0.0.1)
   ANY = 1      // All IP addresses
};

#define SOCKET_READ_BUFFER_SIZE  10000

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
   //int addr;//4 bytes, 0 /* INADDR_ANY */ or 0x100007F /* 127.0.0.1 */
   ulong addr;//8 bytes
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
   
   //convert string of IP to ulong for binary to send
   ulong inet_addr(char&[]);
   
   
   
   //The htons function converts a u_short from host to TCP/IP network byte order (which is big-endian).
   int htons(int);
   
   //The listen function places a socket in a state in which it is listening for an incoming connection.
   //To accept connections, a socket is first created with the socket() function and bound to a local address with the bind() function. A backlog for incoming connections is specified with listen,and then the connections are accepted with the accept function. Sockets that are connection oriented, those of type SOCK_STREAM for example, are used with listen. 
   int listen(int, int);
   // first param = int return from socket()
   // second = The maximum length of the queue of pending connections.
   /*Return value
   If no error occurs, listen returns zero. Otherwise, a value of SOCKET_ERROR(-1) is returned, and a specific error code can be retrieved by calling WSAGetLastError.*/
   
   int connect(int,sockaddr_in&,int);
   
   //The accept function permits an incoming connection attempt on a socket.
   int accept(int, int, int);
   //1st = int returned from socket()
   //2nd = pointer to keep client address value (same format with establish)
   //3rd = (2nd param'lenght) address length
   
   
   int closesocket(int);
   int select(int, fd_set&, fd_set&, int, timeval&);
   int select(int, fd_set64&, fd_set64&, int, timeval&);  // See notes to socketselect3264() below
   int recv(int, uchar&[], int, int);
   int ioctlsocket(int, uint, uint&);
   int WSAGetLastError();
   int WSAAsyncSelect(int, int, uint, int);
   int send(int,char&,int,int);
#import   














ulong IPToAddr(string ip)
{
   char ch[]; 
   StringToCharArray(ip,ch);
   ulong result = inet_addr(ch);
   ArrayFree(ch);
   return result;
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
int socketselect3264(int TestSocket)//to test read/write socket
{
   timeval waitfor;
   waitfor.secs = 0;
   waitfor.usecs = 0;

   // The following, incidentally, is permitted on MT4, but obviously returns false...
   if (TerminalInfoInteger(TERMINAL_X64)) {
      fd_set64 PollSocket64;
      PollSocket64.count = 1;
      PollSocket64.single_socket = TestSocket;

      int result= select(0, PollSocket64, PollSocket64, 0, waitfor);
      ArrayFree(PollSocket64.dummy);
      return result;

   } else {
      fd_set PollSocket32;
      PollSocket32.count = 1;
      PollSocket32.single_socket = TestSocket;
   
      int result= select(0, PollSocket32,PollSocket32, 0, waitfor);
      ArrayFree(PollSocket32.dummy);
      return result;
   }
}

//------SERVER CLASS
class SocketServer {
private:
   int _socketid;
   
public:
   SocketServer(AllowedAddressesEnum AcceptFrom,int Port);
   ~SocketServer();
   int SocketID() {return _socketid;}
   bool IsSuccessfulStart;
   bool BindEvent(int hwnd,uint wMsg,int event);
   int AcceptNewClient();
};
SocketServer::SocketServer(AllowedAddressesEnum acceptFrom,int Port)
{
   IsSuccessfulStart = false;
   _socketid = socket(2 /* AF_INET */, 1 /* SOCK_STREAM */, 6 /* IPPROTO_TCP */);
   if (_socketid == -1) {Print("ERROR " , WSAGetLastError() , " in socket creation");return;}
   
   // Put the socket into non-blocking mode
   uint nbmode = 1;
   if (ioctlsocket(_socketid, 0x8004667E /* FIONBIO */, nbmode) != 0) {Print("ERROR in setting non-blocking mode on server socket");return;}
   
   // Bind the socket to the specified port number. In this example,
   // we only accept connections from localhost
   sockaddr_in service;
   service.af_family = 2 /* AF_INET */;
   service.addr = (acceptFrom == ANY ? 0 /* INADDR_ANY */ : IPToAddr("127.0.0.1"));
   service.port = (short)htons(Port);//The htons function converts a u_short from host to TCP/IP network byte order (which is big-endian).
   if (bind(_socketid, service, 16 /* sizeof(service) */) == -1) {Print("ERROR " , WSAGetLastError() , " in socket bind");return;}

   // Put the socket into listening mode
   if (listen(_socketid, 10) == -1) {Print("ERROR " , WSAGetLastError() , " in socket listen");return;}
   IsSuccessfulStart = true;
}
bool SocketServer::BindEvent(int hwnd,uint wMsg,int event)
{
   if (WSAAsyncSelect(_socketid, hwnd, wMsg, event) == 0) {
         return true;
   }
   else return false;
}
//-1 when is not found any new client
int SocketServer::AcceptNewClient(){
   if(Connection::SocketActive(_socketid)>0)
   {
    Print("New incoming connection...");
     int NewClientSocket = accept(_socketid, 0, 0);
      if (NewClientSocket == -1) 
      {
         if (WSAGetLastError() == 10035 /* WSAEWOULDBLOCK */) 
         {
            // Blocking warning; ignore
            Print("... would block; ignore");
         } 
         else 
         {
            Print("ERROR " , WSAGetLastError() , " in socket accept");
         }
         return -1;
      } else 
      {
         Print("...accepted");             
         Print("Got connection to client #", NewClientSocket);
         return NewClientSocket;
      }
   }
   else return -1;
}
SocketServer::~SocketServer()
{
   closesocket(_socketid);
}



//-----------CLIENT CLASS----------------
class SocketClient {
private:
   int _socketid;
   sockaddr_in _service;
public:
   SocketClient(AllowedAddressesEnum connectTo,string ipv4,int Port);
   ~SocketClient();
   bool RenewSocket();
   bool IsServerConnected;
   int SocketID() {return _socketid;}
   bool IsSuccessfulStart;
   bool BindEvent(int hwnd,uint wMsg,int event);
   bool ConnectToServer();
};
SocketClient::SocketClient(AllowedAddressesEnum connectTo,string ipv4,int Port)
{
   IsSuccessfulStart = false;
   IsServerConnected = false;
   _socketid = 0;
   bool isObtainedSocket = RenewSocket();
   if(isObtainedSocket) 
   {
   // Bind the socket to the specified port number. In this example,
   // we only accept connections from localhost
   _service.af_family = 2 /* AF_INET */;
   _service.addr = (connectTo == ANY ? 0 /* INADDR_ANY */ : IPToAddr(ipv4));
   _service.port = (short)htons(Port);//The htons function converts a u_short from host to TCP/IP network byte order (which is big-endian).
   
   bool result = ConnectToServer();
   if(result) 
   {
      IsServerConnected = true;
      Print("CONNECTED!!");
   }
   IsSuccessfulStart = true;
   }
}
bool SocketClient::RenewSocket(void)//ถ้ารู้ตักวว่า disconnected จาก connection ต้อง renew ทันที
{
   if(_socketid!=0) closesocket(_socketid);
   
   _socketid = socket(2 /* AF_INET */, 1 /* SOCK_STREAM */, 6 /* IPPROTO_TCP */);
   if (_socketid == -1) {Print("ERROR " , WSAGetLastError() , " in socket creation");return false ;}
   
   // Put the socket into non-blocking mode
   uint nbmode = 1;
   if (ioctlsocket(_socketid, 0x8004667E /* FIONBIO */, nbmode) != 0) {Print("ERROR in setting non-blocking mode on server socket");return false;}
   
   return true;
}
bool SocketClient::ConnectToServer(void)//call this in while loop for retry the connection, after renew socket
{
     // Connect to server.
     if(!IsServerConnected){
         int connectResult = connect(_socketid,_service, 16);
         if(connectResult == -1) {
            int err = WSAGetLastError();
            if( err == 10056)
            {  
               IsServerConnected = true;
               Print("RECONNECTED!!");
               return true;
            }
            else if( err == 10035 )
            {
                Print("TRY TO CONNECT SERVER...");
               //try hard to connect
               return true;
            }
            else
            {
              //Print("ELSE ",err);
            }
            
        }
    }
    return true;
}
bool SocketClient::BindEvent(int hwnd,uint wMsg,int event)
{
   if (WSAAsyncSelect(_socketid, hwnd, wMsg, event) == 0) {
         return true;
   }
   else return false;
}
SocketClient::~SocketClient()
{
   closesocket(_socketid);
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

   
public:
   Connection(int ClientSocket);
   ~Connection();
   string GetID() {return IntegerToString(mSocket);}
   int SocketHandle() {return mSocket;}
   static int SocketActive(int socketId);   
   bool IsDisconnected;
   int LenthPendingData;//-1 = unavailable, 0=none, >0 pending data
   void CheckPendingData();
   string ProcessIncomingData();
   bool SendData(string data);
   void CloseSocket();
};

// Constructor, called with the handle of a newly accepted socket
Connection::Connection(int SocketID)
{
   IsDisconnected = false;
   mSocket = SocketID; 
   
   // Put the client socket into non-blocking mode
   uint nbmode = 1;
   if (ioctlsocket(mSocket, 0x8004667E /* FIONBIO */, nbmode) != 0) {Print("ERROR in setting non-blocking mode on client socket",WSAGetLastError());}
}

// Destructor. Simply close the client socket
Connection::~Connection()
{
   ArrayFree(mTempBuffer);
  // closesocket(mSocket);
}

void Connection::CloseSocket()
{
   closesocket(mSocket);
}

static int Connection::SocketActive(int socketId)
{
   //Check the client socket for data-read/write-ability
   int selres = socketselect3264(socketId);
     //Print("Active Socket : ", selres);
   if (selres > 0) {
      return selres;
   }
   else if (selres == 0){
     //timeout, time limit expired
     return selres;
   }
   else if(selres == -1){
     //error occurred
     Print("Error Occured in IsSocketActive : Error",WSAGetLastError());
     return selres;
   }
   else return -1;
}

void Connection::CheckPendingData()
{
   if(SocketActive(mSocket)<=0)
   {
     //error , socket dead , time expired
     IsDisconnected = true;
     LenthPendingData= -1;
     return;
   }
   else
   {
      // Winsock says that there is data waiting to be read on this socket
      int szData = recv(mSocket, mTempBuffer, SOCKET_READ_BUFFER_SIZE, 0);
      //Print("szData : ", szData);
      if (szData > 0) {
         IsDisconnected = false;
         LenthPendingData= szData;
         return;
      
      } else if (WSAGetLastError() == 10035 /* WSAEWOULDBLOCK */) {
        IsDisconnected = false;
        LenthPendingData= 0;
         //Print("WSAEWOULDBLOCK");
         // Would block; not an error
         return;
         
      } else {
         IsDisconnected = true;
         LenthPendingData= -1;
         // recv() failed. Assume socket is dead
         return;
      }
   
   } 
}

// shoud further process set of data by delimiter such as | 
string Connection::ProcessIncomingData()
{
   if(!IsDisconnected && LenthPendingData >0)
      return CharArrayToString(mTempBuffer, 0, LenthPendingData);
   else return NULL;
}

bool Connection::SendData(string data)
{
  CheckPendingData();
  if(!IsDisconnected)
  {
    int len =StringLen(data);
    char sendArr[];
    StringToCharArray(data,sendArr);
    send(mSocket,sendArr[0],len,0);
    ArrayFree(sendArr);
    return true;
  }
  else
  {
    return false;
  }
}
