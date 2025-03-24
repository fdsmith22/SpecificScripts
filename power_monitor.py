import time
import os
import datetime
import psutil
import signal
import sys

# Log file path (persistent across reboots)
LOG_FILE = "/home/ubuntu/power_log.txt"

# Track script start time
START_TIME = datetime.datetime.now()

def create_or_append_log():
    """Create log file if it doesn't exist, else append a new section."""
    if not os.path.exists(LOG_FILE):
        with open(LOG_FILE, "w") as log:
            log.write("Power Monitor Log - Jetson Xavier\n")
            log.write("=" * 50 + "\n")
    
    with open(LOG_FILE, "a") as log:
        log.write("=" * 50 + "\n")
        log.write(f"TEST STARTED\n")
        log.write(f"Start Time: {START_TIME.strftime('%Y-%m-%d %H:%M:%S')}\n")
        log.write("=" * 50 + "\n")

def log_power_status():
    """Log system uptime and power details."""
    with open(LOG_FILE, "a") as log:
        timestamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        uptime_seconds = time.time() - psutil.boot_time()
        uptime_str = str(datetime.timedelta(seconds=int(uptime_seconds)))

        # Read power status from power supply
        power_status = "Unknown"
        power_supply_path = "/sys/class/power_supply"
        if os.path.exists(power_supply_path):
            try:
                power_sources = os.listdir(power_supply_path)
                power_status = ""
                for source in power_sources:
                    status_file = f"{power_supply_path}/{source}/status"
                    voltage_file = f"{power_supply_path}/{source}/voltage_now"
                    if os.path.exists(status_file):
                        with open(status_file, "r") as f:
                            power_status += f"{source}: {f.read().strip()} "
                    if os.path.exists(voltage_file):
                        with open(voltage_file, "r") as f:
                            voltage = int(f.read().strip()) / 1_000_000
                            power_status += f"(Voltage: {voltage:.2f}V) "
            except Exception as e:
                power_status = f"Error reading power supply: {e}"

        # GPU load (Jetson-specific)
        gpu_power = "N/A"
        gpu_load_path = "/sys/devices/gpu.0/load"
        if os.path.exists(gpu_load_path):
            try:
                with open(gpu_load_path, "r") as f:
                    gpu_load = int(f.read().strip()) / 10
                gpu_power = f"Load: {gpu_load}%"
            except Exception as e:
                gpu_power = f"Error: {e}"

        # Write log entry
        entry = f"{timestamp} | Uptime: {uptime_str} | Power: {power_status} | GPU Power: {gpu_power}\n"
        log.write(entry)
        print(entry.strip())

def log_end_time():
    """Append session end time and duration."""
    end_time = datetime.datetime.now()
    duration = end_time - START_TIME
    with open(LOG_FILE, "a") as log:
        log.write("\n" + "=" * 50 + "\n")
        log.write("TEST COMPLETED\n")
        log.write(f"Start Time: {START_TIME.strftime('%Y-%m-%d %H:%M:%S')}\n")
        log.write(f"End Time:   {end_time.strftime('%Y-%m-%d %H:%M:%S')}\n")
        log.write(f"Duration:   {duration}\n")
        log.write("=" * 50 + "\n\n")

    print("\n" + "=" * 50)
    print("TEST COMPLETED")
    print(f"Start Time: {START_TIME.strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"End Time:   {end_time.strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"Duration:   {duration}")
    print("=" * 50 + "\n")

def handle_exit(sig, frame):
    """Graceful shutdown on Ctrl+C or system stop."""
    print("\nStopping power monitor...")
    log_end_time()
    sys.exit(0)

if __name__ == "__main__":
    print(f"Starting power monitor. Logging every 30 minutes to {LOG_FILE}...")
    create_or_append_log()

    # Handle Ctrl+C or shutdown
    signal.signal(signal.SIGINT, handle_exit)
    signal.signal(signal.SIGTERM, handle_exit)

    # Log power status every 30 minutes
    while True:
        log_power_status()
        time.sleep(1800)  # 30 minutes

