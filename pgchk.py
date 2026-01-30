#!/usr/bin/env python3
import sys
import subprocess
from http.server import BaseHTTPRequestHandler, HTTPServer
import argparse

# Default configuration
DEFAULT_PORT = 8008
PG_USER = "postgres"
PG_DB = "postgres"
PG_PORT = "5432"

class PostgresHealthCheckHandler(BaseHTTPRequestHandler):
    def safe_write(self, data):
        """Write response body, ignoring errors if client disconnected early.

        Health check clients (HAProxy, curl -sf) often close the connection
        after receiving the status code, before reading the response body.
        This is normal and expected behavior.
        """
        try:
            self.wfile.write(data)
        except (BrokenPipeError, ConnectionResetError) as e:
            # Client disconnected early - normal for health checks that only need status code
            print(f"Client disconnected early ({type(e).__name__}): {self.path}")

    def check_postgres_status(self):
        """
        Checks if the local PostgreSQL instance is in recovery mode.
        Returns:
            True if in recovery (Standby)
            False if not in recovery (Primary)
            None if check fails
        """
        try:
            # Execute psql command to check recovery status
            # We use subprocess to avoid needing psycopg2 dependency
            cmd = [
                "psql",
                "-U", PG_USER,
                "-d", PG_DB,
                "-p", PG_PORT,
                "-t",
                "-c", "SELECT pg_is_in_recovery();"
            ]
            
            # Run command
            result = subprocess.run(
                cmd, 
                capture_output=True, 
                text=True, 
                timeout=5
            )
            
            if result.returncode != 0:
                print(f"Error executing psql: {result.stderr}")
                return None

            output = result.stdout.strip()
            if output == 't':
                return True  # Standby
            elif output == 'f':
                return False # Primary
            else:
                print(f"Unexpected output from psql: {output}")
                return None
                
        except Exception as e:
            print(f"Exception checking postgres: {e}")
            return None

    def do_GET(self):
        status = self.check_postgres_status()
        
        if status is None:
            self.send_response(503)
            self.end_headers()
            self.safe_write(b"PostgreSQL Unreachable\n")
            return

        is_standby = status
        is_primary = not status

        if self.path == '/master' or self.path == '/':
            if is_primary:
                self.send_response(200)
                self.end_headers()
                self.safe_write(b"OK - Primary\n")
            else:
                self.send_response(503)
                self.end_headers()
                self.safe_write(b"Service Unavailable - Not Primary\n")
                
        elif self.path == '/replica':
            if is_standby:
                self.send_response(200)
                self.end_headers()
                self.safe_write(b"OK - Replica\n")
            else:
                self.send_response(503)
                self.end_headers()
                self.safe_write(b"Service Unavailable - Not Replica\n")

        elif self.path == '/ready':
            # Returns 200 for any healthy PostgreSQL (primary or standby)
            # Used by HAProxy as fallback when all standbys are down
            self.send_response(200)
            self.end_headers()
            role = "Replica" if is_standby else "Primary"
            self.safe_write(f"OK - Ready ({role})\n".encode())
        else:
            self.send_response(404)
            self.end_headers()
            self.safe_write(b"Not Found\n")

    def log_message(self, format, *args):
        # Disable logging to stdout/stderr for clean output, or keep it for debugging
        # sys.stderr.write("%s - - [%s] %s\n" % (self.address_string(), self.log_date_time_string(), format%args))
        pass

def run(server_class=HTTPServer, handler_class=PostgresHealthCheckHandler, port=DEFAULT_PORT):
    server_address = ('', port)
    httpd = server_class(server_address, handler_class)
    print(f"Starting PostgreSQL Health Check on port {port}...")
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass
    httpd.server_close()
    print("Server stopped.")

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='PostgreSQL Health Check for HAProxy')
    parser.add_argument('--port', type=int, default=DEFAULT_PORT, help=f'Port to listen on (default: {DEFAULT_PORT})')
    args = parser.parse_args()
    
    run(port=args.port)
