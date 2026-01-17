import React, { createContext, useContext, useState, useEffect, useMemo } from "react";

/**
 * Context for JSON stream messages from broadcast_json_to
 */
const JsonStreamContext = createContext(null);

/**
 * Hook to access the JSON stream context
 * @returns {{ lastMessage: any, connected: boolean, stream: string }}
 */
export function useJsonStream() {
  const context = useContext(JsonStreamContext);
  if (!context) {
    throw new Error("useJsonStream must be used within a JsonStreamProvider");
  }
  return context;
}

/**
 * Provider component that handles WebSocket/BroadcastChannel subscription
 *
 * Automatically detects target:
 * - Browser target: uses BroadcastChannel for same-origin tab sync
 * - Node target: uses WebSocket to server for cross-client sync
 *
 * @param {Object} props
 * @param {string} props.stream - Channel name to subscribe to (e.g., "workflow_123")
 * @param {string} [props.endpoint="/cable"] - WebSocket endpoint path
 * @param {React.ReactNode} props.children - React children to render
 */
export default function JsonStreamProvider({ stream, endpoint = "/cable", children }) {
  const [lastMessage, setLastMessage] = useState(null);
  const [connected, setConnected] = useState(false);

  useEffect(() => {
    // Browser target: use BroadcastChannel (no WebSocket needed)
    // Node target: use WebSocket to server
    if (typeof BroadcastChannel !== "undefined") {
      // Browser target - BroadcastChannel for same-origin tabs
      const channel = new BroadcastChannel(stream);
      setConnected(true);

      channel.onmessage = (event) => {
        setLastMessage(event.data);
      };

      return () => {
        channel.close();
        setConnected(false);
      };
    } else {
      // Node target - WebSocket to server
      const protocol = window.location.protocol === "https:" ? "wss:" : "ws:";
      const ws = new WebSocket(`${protocol}//${window.location.host}${endpoint}`);

      ws.onopen = () => {
        ws.send(JSON.stringify({ type: "subscribe", stream }));
        setConnected(true);
      };

      ws.onmessage = (event) => {
        const msg = JSON.parse(event.data);
        if (msg.type !== "message") return;
        const payload = JSON.parse(msg.message);
        setLastMessage(payload);
      };

      ws.onerror = (error) => {
        console.error("JsonStreamProvider error:", error);
      };

      ws.onclose = () => {
        setConnected(false);
      };

      return () => {
        if (ws.readyState === WebSocket.OPEN) {
          ws.send(JSON.stringify({ type: "unsubscribe", stream }));
        }
        ws.close();
      };
    }
  }, [stream, endpoint]);

  const value = useMemo(
    () => ({ lastMessage, connected, stream }),
    [lastMessage, connected, stream]
  );

  return React.createElement(
    JsonStreamContext.Provider,
    { value },
    children
  );
}
