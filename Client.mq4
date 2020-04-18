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
#include "../Include/Winsock.mqh"

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

// User inputs
input int loopMilliSecond = 500;
input int                     PortNumber = 51234;     // TCP/IP port number
input AllowedAddressesEnum    ConnectTo = LOCALTHOST;  // Accept connections from
input string    IP = "127.0.0.1";  // Accept connections from

// ---------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------


// Defines the frequency of the main-loop processing, in milliseconds.
// This is either the duration of the sleep in OnStart(), if compiled
// as a script, or the frequency which is given to EventSetMillisecondTimer()
// if compiled as an EA. (In the context of an EA, the use of additional
// event-driven handling means that the timer is only a fallback, and
// this value could be set to a larger value, just acting as a sweep-up)
#define SLEEP_MILLISECONDS       loopMilliSecond

// ---------------------------------------------------------------------
// Global variables
// ---------------------------------------------------------------------

// Flags whether OnInit was successful
bool SuccessfulInit = false;

bool IsServerConnected = false;

Connection * Server;

SocketClient * Client;

#ifdef COMPILE_AS_EA
// For EA compilation only, we track whether we have 
// successfully created a timer
bool CreatedTimer = false;   

// For EA compilation only, we track whether we have 
// done WSAAsyncSelect(), which can't reliably done in OnInit()
// because a chart handle isn't necessarily available
bool DoneAsyncSelect = false;
#endif


void OnInit()
{
   SuccessfulInit = false;
   
   if (!TerminalInfoInteger(TERMINAL_DLLS_ALLOWED)) {Print("Requires \'Allow DLL imports\'");return;}
   
   // (Don't need to call WSAStartup because MT4 must have done this)
   
   Client = new SocketClient(ConnectTo,IP,PortNumber);
   if(!Client.IsSuccessfulStart) return;

   if(Client.IsServerConnected) Server = new Connection(Client.SocketID());
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
       if (Client.BindEvent((int)ChartGetInteger(0, CHART_WINDOW_HANDLE), 0x100 /* WM_KEYDOWN */, 0xFF /* All events */)) {
         DoneAsyncSelect = true;
      }
   }

   // In an EA, the use of WSAAsyncSelect() above means that Windows will fire a key-down 
   // message whenever there is socket activity. We can then respond to KEYDOWN events
   // in MQL4 as a way of knowing that there is socket activity to be dealt with.
   void OnChartEvent(const int id, const long& lparam, const double& dparam, const string& sparam)
   {
      //lparam is socket id which event occured****
      if (id == CHARTEVENT_KEYDOWN) {
         // For a pseudo-keypress from WSAAsyncSelect(), the lparam will be the socket handle
         // (and the dparam will be the type of socket event, e.g. dparam = 1 = FD_READ).
         // Of course, this event can also be fired for real keypresses on the chart...

            // See if lparam is server or not
            if (Client.SocketID() == lparam) {
                  if (Client.IsServerConnected && Server!= NULL) {
                     //Socket is connect
                     Server.CheckPendingData();//indicate connection is lost or not
                     if(!Server.IsDisconnected)
                     {
                       HandleServerMsg(Server);
                     }
                     else
                     {
                       //disconnect known by data detecting --> need to renew, Set Null to server
                       delete(Server);//not sure double call closesocket
                       Server = NULL;
                       Client.IsServerConnected = false;
                       Client.RenewSocket();//we renew only we have once have server and lost it, so we renew when setting server to null only
                       ReConnectToServer();
                     }
                     
                  }
                  else{
                    Client.IsServerConnected = false;
                   //Disconnected, try to reconnect
                   ReConnectToServer();
                  } 
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
                 if (Client.IsServerConnected && Server!= NULL) {
                     //Socket is connect
                     Server.CheckPendingData();//indicate connection is lost or not
                     if(!Server.IsDisconnected)
                     {
                       HandleServerMsg(Server);
                     }
                     else
                     {
                       //disconnect known by data detecting --> need to renew, Set Null to server
                       Server.CloseSocket();
                       delete(Server);//not sure double call closesocket
                       Server = NULL;
                       Client.IsServerConnected = false;
                       Client.RenewSocket();//we renew only we have once have server and lost it, so we renew when setting server to null only
                       ReConnectToServer();
                     }
                     
                  }
                  else{
                    Client.IsServerConnected = false;
                   //Disconnected, try to reconnect
                   ReConnectToServer();
                  }   
}

// Accept any new pending connections on the main listening server socket,
// wrapping the new caller in a Connection object and putting it
// into the Clients[] array

void HandleServerMsg(Connection * server)
{
               if(server.LenthPendingData>0)
               {
                string data = server.ProcessIncomingData();
                Print("#",Server.GetID()," says :",data);
               }
}

void ReConnectToServer()
{
     bool isConnected = Client.ConnectToServer();
     delete(Server);//we will not set NUll to server
     Server = new Connection(Client.SocketID());//Client.SocketID() is renewed not always;
}
// ---------------------------------------------------------------------
// Termination - clean up sockets
// ---------------------------------------------------------------------

void OnDeinit(const int reason)
{
   //Called when period changed
   delete(Server);
   Server = NULL;
   //Client.IsServerConnected = false;
   //Client.RenewSocket();
   
   delete(Client);
   Client = NULL;
   
   #ifdef COMPILE_AS_EA
   EventKillTimer();
   CreatedTimer = false;
   DoneAsyncSelect = false;
   #endif
}

