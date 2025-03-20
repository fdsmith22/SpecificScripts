



import time
import os
import datetime
import psutil
import signal
import sys

# Log file path (new file each run)
LOG_FILE = "/home/ubuntu/power_log.txt"

# Track start time
START_TIME = datetime.datetime.now()

def create_new_log():
    """Creates a new log file at /home/power_log.txt (overwriting old logs)."""
    with open(LOG_FILE, "w") as log:
        log.write("Power Monitor Log - Jetson Xavier\n")
        log.write("=" * 50 + "\n")
        log.write(f"TEST STARTED\n")
        log.write(f"Start Time: {START_TIME.strftime('%Y-%m-%d %H:%M:%S')}\n")
        log.write("=" * 50 + "\n")

def log_power_status():
    """Logs system power status and uptime."""
    with open(LOG_FILE, "a") as log:
        timestamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")

        # Get uptime in seconds
        uptime_seconds = time.time() - psutil.boot_time()
        uptime_str = str(datetime.timedelta(seconds=int(uptime_seconds)))

        # Check power status from `/sys/class/power_supply`
        power_status = "Unknown"
        power_supply_path = "/sys/class/power_supply"
        if os.path.exists(power_supply_path):
            try:
                power_sources = os.listdir(power_supply_path)
                if power_sources:
                    power_status = ""
                    for source in power_sources:
                        status_file = f"{power_supply_path}/{source}/status"
                        voltage_file = f"{power_supply_path}/{source}/voltage_now"
                        if os.path.exists(status_file):
                            with open(status_file, "r") as f:
                                power_status += f"{source}: {f.read().strip()} "
                        if os.path.exists(voltage_file):
                            with open(voltage_file, "r") as f:
                                voltage = int(f.read().strip()) / 1_000_000  # Convert µV to V
                                power_status += f"(Voltage: {voltage:.2f}V) "
            except Exception as e:
                power_status = f"Error reading power status: {e}"

        # Get GPU power info for Jetson Xavier
        gpu_power = "N/A"
        if os.path.exists("/sys/devices/gpu.0/load"):
            try:
                with open("/sys/devices/gpu.0/load", "r") as f:
                    gpu_load = int(f.read().strip()) / 10  # Convert to percentage
                gpu_power = f"Load: {gpu_load}%"
            except Exception as e:
                gpu_power = f"Error: {e}"

        # Log entry
        log_entry = f"{timestamp} | Uptime: {uptime_str} | Power: {power_status} | GPU Power: {gpu_power}\n"
        log.write(log_entry)
        print(log_entry.strip())

def log_end_time():
    """Logs the end time and total duration when script stops."""
    end_time = datetime.datetime.now()
    total_duration = end_time - START_TIME

    with open(LOG_FILE, "a") as log:
        log.write("\n" + "=" * 50 + "\n")
        log.write(f"TEST COMPLETED\n")
        log.write(f"Start Time: {START_TIME.strftime('%Y-%m-%d %H:%M:%S')}\n")
        log.write(f"End Time: {end_time.strftime('%Y-%m-%d %H:%M:%S')}\n")
        log.write(f"Total Duration: {total_duration}\n")
        log.write("=" * 50 + "\n\n")

    print("\n" + "=" * 50)
    print(f"TEST COMPLETED")
    print(f"Start Time: {START_TIME.strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"End Time: {end_time.strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"Total Duration: {total_duration}")
    print("=" * 50 + "\n")

# Handle script termination gracefully
def signal_handler(sig, frame):
    print("\nStopping power monitoring...")
    log_end_time()
    sys.exit(0)

if __name__ == "__main__":
    print(f"Starting power monitor. Logging to {LOG_FILE} every 30 minutes...")

    create_new_log()

    # Capture Ctrl+C or system shutdown
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)

    # Monitoring loop (every 30 minutes)
    while True:
        log_power_status()
        time.sleep(1800)  # 1800 seconds = 30 minutes

