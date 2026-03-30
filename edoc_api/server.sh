#!/bin/bash
# Phoenix Server Management Script for Edoc API

PID_FILE="/tmp/edoc_api_server.pid"
LOG_FILE="/tmp/edoc_server.log"
MIX_CMD="/home/biba/.asdf/shims/mix phx.server"

start() {
    if [ -f "$PID_FILE" ] && kill -0 $(cat "$PID_FILE") 2>/dev/null; then
        echo "Server is already running (PID: $(cat $PID_FILE))"
        exit 1
    fi

    echo "Starting Phoenix server..."
    cd /home/biba/codes/e-doc/edoc_api
    nohup $MIX_CMD > "$LOG_FILE" 2>&1 &
    echo $! > "$PID_FILE"
    disown $! 2>/dev/null || true
    sleep 2

    if kill -0 $(cat "$PID_FILE") 2>/dev/null; then
        echo "Server started successfully (PID: $(cat $PID_FILE))"
        echo "Log file: $LOG_FILE"
    else
        echo "Failed to start server. Check logs: $LOG_FILE"
        rm -f "$PID_FILE"
        exit 1
    fi
}

stop() {
    if [ ! -f "$PID_FILE" ]; then
        echo "PID file not found. Server may not be running."
        # Try to find and kill anyway
        pids=$(pgrep -f "phx.server" || true)
        if [ -n "$pids" ]; then
            echo "Killing phx.server processes: $pids"
            echo "$pids" | xargs kill -TERM 2>/dev/null || true
            sleep 2
            echo "$pids" | xargs kill -KILL 2>/dev/null || true
        fi
        return
    fi

    pid=$(cat "$PID_FILE")
    if kill -0 $pid 2>/dev/null; then
        echo "Stopping server (PID: $pid)..."
        kill -TERM $pid
        sleep 3
        if kill -0 $pid 2>/dev/null; then
            echo "Force killing server..."
            kill -KILL $pid
        fi
        echo "Server stopped"
    else
        echo "Server not running (stale PID file)"
    fi
    rm -f "$PID_FILE"
}

status() {
    if [ -f "$PID_FILE" ]; then
        pid=$(cat "$PID_FILE")
        if kill -0 $pid 2>/dev/null; then
            echo "Server is running (PID: $pid)"
            echo "Log file: $LOG_FILE"
            ps -p $pid -o pid,ppid,cmd
        else
            echo "Server not running (stale PID file)"
        fi
    else
        pids=$(pgrep -f "phx.server" || true)
        if [ -n "$pids" ]; then
            echo "Server is running (PIDs: $pids)"
            echo "Note: No PID file found"
        else
            echo "Server is not running"
        fi
    fi
}

logs() {
    if [ -f "$LOG_FILE" ]; then
        tail -f "$LOG_FILE"
    else
        echo "Log file not found: $LOG_FILE"
    fi
}

case "$1" in
    start)
        start
        ;;
    stop)
        stop
        ;;
    restart)
        stop
        sleep 2
        start
        ;;
    status)
        status
        ;;
    logs)
        logs
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status|logs}"
        exit 1
        ;;
esac
