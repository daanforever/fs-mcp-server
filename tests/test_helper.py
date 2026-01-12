#!/usr/bin/env python3
"""Common helper functions for MCP File Edit Server tests"""

import json
import subprocess
import time
import os

# Default server path (can be overridden)
SERVER = os.environ.get("SERVER", "./mcp-file-edit")

# Test counters
PASSED = 0
FAILED = 0


def send_mcp_request(request, timeout=5):
    """Send MCP request with proper initialization"""
    try:
        proc = subprocess.Popen(
            [SERVER],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=1
        )
        
        # Send initialize
        init_req = {
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize",
            "params": {
                "protocolVersion": "2024-11-05",
                "capabilities": {},
                "clientInfo": {"name": "test", "version": "1.0.0"}
            }
        }
        proc.stdin.write(json.dumps(init_req) + "\n")
        proc.stdin.flush()
        time.sleep(0.1)
        
        # Send initialized notification
        notif = {
            "jsonrpc": "2.0",
            "method": "notifications/initialized",
            "params": {}
        }
        proc.stdin.write(json.dumps(notif) + "\n")
        proc.stdin.flush()
        time.sleep(0.1)
        
        # Send actual request
        proc.stdin.write(json.dumps(request) + "\n")
        proc.stdin.flush()
        time.sleep(1.0)
        
        # Read all responses
        responses = []
        proc.stdin.close()
        
        # Try to read all available lines
        start_time = time.time()
        while time.time() - start_time < timeout:
            # Check if process is still running
            if proc.poll() is not None:
                # Process ended, read remaining output
                remaining = proc.stdout.read()
                if remaining:
                    for line in remaining.split('\n'):
                        if line.strip():
                            try:
                                resp = json.loads(line.strip())
                                if resp.get("id") != 1:
                                    responses.append(resp)
                            except json.JSONDecodeError:
                                continue
                break
            
            # Try to read available lines
            try:
                # Use non-blocking read if available
                if hasattr(proc.stdout, 'readline'):
                    line = proc.stdout.readline()
                    if line:
                        try:
                            resp = json.loads(line.strip())
                            if resp.get("id") != 1:
                                responses.append(resp)
                        except json.JSONDecodeError:
                            continue
                    else:
                        time.sleep(0.1)
                else:
                    time.sleep(0.1)
            except:
                time.sleep(0.1)
        
        # Cleanup
        try:
            proc.terminate()
            proc.wait(timeout=1)
        except:
            try:
                proc.kill()
            except:
                pass
        
        # Return last non-initialize response
        if responses:
            return responses[-1]
        return None
        
    except subprocess.TimeoutExpired:
        try:
            proc.kill()
        except:
            pass
        return None
    except Exception as e:
        try:
            proc.kill()
        except:
            pass
        return None


def test_case(name, test_cmd, expected_check):
    """Run a test case and track results"""
    global PASSED, FAILED
    
    print(f"  {name}: ", end="", flush=True)
    
    try:
        result = test_cmd()
        if expected_check(result):
            print("PASS")
            PASSED += 1
        else:
            print("FAIL")
            print(f"    Result: {result}")
            FAILED += 1
    except Exception as e:
        print(f"FAIL (error: {e})")
        FAILED += 1


def print_test_results():
    """Print test results summary"""
    global PASSED, FAILED
    
    print()
    print("=== Результаты ===")
    print(f"Пройдено: {PASSED}")
    print(f"Провалено: {FAILED}")
    print()
    
    if FAILED == 0:
        print("Все тесты пройдены успешно!")
        return 0
    else:
        print("Некоторые тесты провалились.")
        return 1
