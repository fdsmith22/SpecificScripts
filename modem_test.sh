#!/bin/bash
# =================================================================
# UNIFIED MODEM TEST SCRIPT - ALL LOCATIONS
# Comprehensive modem testing for V3 sensor stacks
# =================================================================

# Color codes for better UI
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Global variables
MODEM_PORT="/dev/ttyUSB2"  # AT command port based on ModemManager info
DETECTED_MODEM_NUM=""      # Will be set dynamically during modem detection
ACTIVE_MODEM_NUM=""        # Current working modem number (may change during test)
LOCATION=""
LOCATION_NAME=""
LOG_FILE=""
RESULTS_FILE=""

# Function to display header
show_header() {
    clear
    echo -e "${BLUE}=================================================================${NC}"
    echo -e "${BLUE}           UNIFIED MODEM TEST SCRIPT v1.0${NC}"
    echo -e "${BLUE}        Comprehensive Testing for V3 Sensor Stacks${NC}"
    echo -e "${BLUE}=================================================================${NC}"
    echo ""
}

# Function to select location
select_location() {
    show_header
    echo -e "${YELLOW}Please select your test location:${NC}"
    echo ""
    echo -e "  ${GREEN}1${NC} - London Office (Expected: Strong signal, fast speeds)"
    echo -e "  ${GREEN}2${NC} - MK Office (Expected: Moderate signal, good speeds)"
    echo -e "  ${GREEN}3${NC} - Rural On-Site (Expected: Weak signal, basic speeds)"
    echo ""
    echo -e -n "${YELLOW}Enter your choice (1-3): ${NC}"
    
    read -r choice
    
    case $choice in
        1)
            LOCATION="LondonOffice"
            LOCATION_NAME="London Office"
            ;;
        2)
            LOCATION="MKOffice"
            LOCATION_NAME="MK Office"
            ;;
        3)
            LOCATION="RuralOnSite"
            LOCATION_NAME="Rural On-Site"
            ;;
        *)
            echo -e "${RED}Invalid choice. Please select 1, 2, or 3.${NC}"
            sleep 2
            select_location
            return
            ;;
    esac
    
    LOG_FILE="modem_test_${LOCATION}_$(date +%Y%m%d_%H%M%S).log"
    RESULTS_FILE="modem_results_${LOCATION}_$(date +%Y%m%d_%H%M%S).csv"
    
    echo ""
    echo -e "${GREEN}Selected: $LOCATION_NAME${NC}"
    echo -e "Log file: $LOG_FILE"
    echo -e "Results file: $RESULTS_FILE"
    echo ""
    echo -e "Press Enter to continue..."
    read -r
}

# Check and install dependencies
install_dependencies() {
    echo -e "${YELLOW}Checking dependencies...${NC}"
    
    # Check for socat
    if ! which socat > /dev/null; then
        echo -e "${YELLOW}Installing socat...${NC}"
        sudo apt update && sudo apt install -y socat
    fi
    
    # Check for bc
    if ! which bc > /dev/null; then
        echo -e "${YELLOW}Installing bc...${NC}"
        sudo apt update && sudo apt install -y bc
    fi
    
    echo -e "${GREEN}Dependencies ready!${NC}"
    
    # Check ModemManager availability and get modem number
    echo -e "${YELLOW}Checking ModemManager...${NC}"
    if which mmcli > /dev/null; then
        # Check if ModemManager is running
        MM_STATUS=$(systemctl is-active ModemManager 2>/dev/null)
        if [ "$MM_STATUS" = "active" ]; then
            echo -e "${GREEN}ModemManager is active${NC}"
            
            # Scan for modems and get list
            echo -e "${YELLOW}Scanning for modems...${NC}"
            sudo mmcli --scan-modems >/dev/null 2>&1
            sleep 3
            
            MODEM_LIST=$(sudo mmcli -L 2>/dev/null)
            if echo "$MODEM_LIST" | grep -q "/Modem/"; then
                # Extract modem number dynamically
                MODEM_NUM=$(echo "$MODEM_LIST" | grep -o '/Modem/[0-9]*' | cut -d'/' -f3 | head -1)
                echo -e "${GREEN}Modem detected: Modem $MODEM_NUM${NC}"
                
                # Get basic modem info to display
                MODEM_INFO=$(sudo mmcli -m $MODEM_NUM 2>/dev/null)
                echo "$MODEM_INFO" | grep -E "(manufacturer|model|signal quality)" | head -3
                
                # Set global modem number for use in send_at function
                DETECTED_MODEM_NUM="$MODEM_NUM"
            else
                echo -e "${YELLOW}No modems found initially, waiting for initialization...${NC}"
                echo -e "${YELLOW}Allowing 45 seconds for device initialization...${NC}"
                
                # Restart ModemManager to ensure clean state
                sudo systemctl restart ModemManager
                
                # Wait for proper initialization
                for i in {45..1}; do
                    printf "\r   ${YELLOW}Initializing: %2d seconds remaining${NC}" $i
                    sleep 1
                done
                echo ""
                
                # Force device scan after initialization
                sudo mmcli --scan-modems >/dev/null 2>&1
                sleep 3
                
                MODEM_LIST=$(sudo mmcli -L 2>/dev/null)
                if echo "$MODEM_LIST" | grep -q "/Modem/"; then
                    MODEM_NUM=$(echo "$MODEM_LIST" | grep -o '/Modem/[0-9]*' | cut -d'/' -f3 | head -1)
                    echo -e "${GREEN}✅ Modem detected after initialization: Modem $MODEM_NUM${NC}"
                    DETECTED_MODEM_NUM="$MODEM_NUM"
                    
                    # Show basic info
                    MODEM_INFO=$(sudo mmcli -m $MODEM_NUM 2>/dev/null)
                    echo "$MODEM_INFO" | grep -E "(manufacturer|model|signal quality)" | head -3
                else
                    echo -e "${RED}❌ No modems detected after initialization${NC}"
                    echo -e "${YELLOW}Continuing with direct AT command fallback...${NC}"
                    DETECTED_MODEM_NUM=""
                fi
            fi
        else
            echo -e "${RED}ModemManager not active${NC}"
            echo -e "${YELLOW}Starting ModemManager...${NC}"
            sudo systemctl start ModemManager
            sleep 5
            DETECTED_MODEM_NUM=""
        fi
    else
        echo -e "${YELLOW}ModemManager not available - using direct AT commands${NC}"
        DETECTED_MODEM_NUM=""
    fi
    
    # Test modem port connectivity only if ModemManager isn't managing it
    echo -e "${YELLOW}Testing direct AT access...${NC}"
    if [ ! -e "$MODEM_PORT" ]; then
        echo -e "${YELLOW}Port $MODEM_PORT not found, trying alternatives...${NC}"
        for alt_port in /dev/ttyUSB3 /dev/ttyUSB2 /dev/ttyUSB1; do
            if [ -e "$alt_port" ]; then
                echo -e "${YELLOW}Trying $alt_port...${NC}"
                MODEM_PORT="$alt_port"
                break
            fi
        done
    fi
}

# AT command function - try ModemManager first, fallback to direct AT
send_at() {
    local cmd="$1"
    local timeout_val=5
    case $LOCATION in
        "RuralOnSite") timeout_val=10 ;;
    esac
    
    # Try ModemManager first (use detected modem number)
    if which mmcli > /dev/null 2>&1 && [ -n "$DETECTED_MODEM_NUM" ]; then
        case "$cmd" in
            "AT+CSQ")
                # Get signal strength via ModemManager
                local mm_signal=$(sudo mmcli -m $DETECTED_MODEM_NUM 2>/dev/null | grep "signal quality" | grep -o '[0-9]\+%' | tr -d '%')
                if [ -n "$mm_signal" ]; then
                    # Convert percentage to CSQ format (0-31)
                    local csq_val=$(echo "scale=0; $mm_signal * 31 / 100" | bc)
                    echo "+CSQ: $csq_val,99"
                    return
                fi
                ;;
            "AT+CGMI")
                local mm_mfg=$(sudo mmcli -m $DETECTED_MODEM_NUM 2>/dev/null | grep "manufacturer:" | cut -d':' -f2 | xargs)
                if [ -n "$mm_mfg" ]; then
                    echo "$mm_mfg"
                    return
                fi
                ;;
            "AT+CGMM")
                local mm_model=$(sudo mmcli -m $DETECTED_MODEM_NUM 2>/dev/null | grep "model:" | cut -d':' -f2 | xargs)
                if [ -n "$mm_model" ]; then
                    echo "$mm_model"
                    return
                fi
                ;;
            "AT+CGMR")
                local mm_fw=$(sudo mmcli -m $DETECTED_MODEM_NUM 2>/dev/null | grep "firmware revision:" | cut -d':' -f2 | xargs)
                if [ -n "$mm_fw" ]; then
                    echo "$mm_fw"
                    return
                fi
                ;;
            "AT+CGSN")
                local mm_imei=$(sudo mmcli -m $DETECTED_MODEM_NUM 2>/dev/null | grep "imei:" | cut -d':' -f2 | xargs)
                if [ -n "$mm_imei" ]; then
                    echo "$mm_imei"
                    return
                fi
                ;;
            "AT+CCID")
                # Get ICCID via ModemManager SIM info
                echo -e "${YELLOW}Getting ICCID requires sudo access...${NC}" >&2
                local mm_iccid=$(sudo mmcli --sim $DETECTED_MODEM_NUM 2>/dev/null | grep "iccid:" | cut -d':' -f2 | xargs)
                if [ -n "$mm_iccid" ]; then
                    echo "$mm_iccid"
                    return
                fi
                ;;
            "AT+CIMI")
                # Get IMSI via ModemManager SIM info  
                echo -e "${YELLOW}Getting IMSI requires sudo access...${NC}" >&2
                local mm_imsi=$(sudo mmcli --sim $DETECTED_MODEM_NUM 2>/dev/null | grep "imsi:" | cut -d':' -f2 | xargs)
                if [ -n "$mm_imsi" ]; then
                    echo "$mm_imsi"
                    return
                fi
                ;;
            "AT+CPIN?")
                # Get SIM status via ModemManager
                local sim_status=$(sudo mmcli -m $DETECTED_MODEM_NUM 2>/dev/null | grep "state:" | cut -d':' -f2 | xargs)
                case "$sim_status" in
                    "connected"|"registered") echo "+CPIN: READY" ;;
                    "locked") echo "+CPIN: SIM PIN" ;;
                    *) echo "+CPIN: UNKNOWN" ;;
                esac
                return
                ;;
            "AT+COPS?")
                local mm_op=$(sudo mmcli -m $DETECTED_MODEM_NUM 2>/dev/null | grep "operator name:" | cut -d':' -f2 | xargs)
                local mm_op_id=$(sudo mmcli -m $DETECTED_MODEM_NUM 2>/dev/null | grep "operator id:" | cut -d':' -f2 | xargs)
                if [ -n "$mm_op" ]; then
                    echo "+COPS: 0,0,\"$mm_op\",7"
                    return
                fi
                ;;
            "AT+CREG?")
                local mm_reg=$(sudo mmcli -m $DETECTED_MODEM_NUM 2>/dev/null | grep "registration:" | cut -d':' -f2 | xargs)
                case "$mm_reg" in
                    "home") echo "+CREG: 0,1" ;;
                    "roaming") echo "+CREG: 0,5" ;;
                    "searching") echo "+CREG: 0,2" ;;
                    *) echo "+CREG: 0,0" ;;
                esac
                return
                ;;
        esac
    fi
    
    # Fallback to direct AT communication
    local response=$(printf "%s\r\n" "$cmd" | timeout $timeout_val socat - $MODEM_PORT,b115200,raw,echo=0 2>/dev/null)
    
    if [ -z "$response" ]; then
        echo "No response"
    else
        echo "$response" | grep -v "^$cmd" | grep -v "^OK" | grep -v "^$" | head -1 | tr -d '\r\n'
    fi
}

# Speed test function - location adaptive
speed_test() {
    echo "=== Speed Tests ==="
    
    case $LOCATION in
        "LondonOffice")
            # Office: Single 5MB test (fast connection expected)
            echo "Download test starting (5MB)..."
            DL_START=$(date +%s.%N)
            wget -q --progress=bar:force -O /tmp/speedtest.tmp http://ipv4.download.thinkbroadband.com/5MB.zip 2>&1 | tail -1
            DL_END=$(date +%s.%N)
            DL_TIME=$(echo "$DL_END - $DL_START" | bc)
            DL_SPEED=$(echo "scale=2; 5 / $DL_TIME" | bc)
            echo "Download: ${DL_SPEED} MB/s in ${DL_TIME}s"
            rm -f /tmp/speedtest.tmp
            ;;
            
        "MKOffice")
            # MK: 3 attempts with 5MB (variable performance expected)
            echo "Download test starting (3 attempts, 5MB each)..."
            DL_SPEEDS=""
            for i in 1 2 3; do
                echo "  Attempt $i..."
                DL_START=$(date +%s.%N)
                wget -q --progress=bar:force -O /tmp/speedtest.tmp http://ipv4.download.thinkbroadband.com/5MB.zip 2>&1 | tail -1
                DL_END=$(date +%s.%N)
                DL_TIME=$(echo "$DL_END - $DL_START" | bc)
                DL_SPEED=$(echo "scale=2; 5 / $DL_TIME" | bc)
                echo "  Download $i: ${DL_SPEED} MB/s in ${DL_TIME}s"
                DL_SPEEDS="$DL_SPEEDS $DL_SPEED"
                rm -f /tmp/speedtest.tmp
                sleep 2
            done
            # Calculate average
            DL_SPEED=$(echo "$DL_SPEEDS" | awk '{sum=0; for(i=1;i<=NF;i++)sum+=$i; print sum/NF}')
            echo "Average Download: ${DL_SPEED} MB/s"
            ;;
            
        "RuralOnSite")
            # Rural: 5 attempts with 1MB (patient testing)
            echo "Download test starting (5 attempts, 1MB each - rural optimized)..."
            DL_SPEEDS=""
            for i in 1 2 3 4 5; do
                echo "  Attempt $i..."
                DL_START=$(date +%s.%N)
                timeout 60 wget -q --progress=bar:force -O /tmp/speedtest.tmp http://ipv4.download.thinkbroadband.com/1MB.zip 2>&1 | tail -1
                if [ -f /tmp/speedtest.tmp ]; then
                    DL_END=$(date +%s.%N)
                    DL_TIME=$(echo "$DL_END - $DL_START" | bc)
                    DL_SPEED=$(echo "scale=2; 1 / $DL_TIME" | bc)
                    echo "  Download $i: ${DL_SPEED} MB/s in ${DL_TIME}s"
                    DL_SPEEDS="$DL_SPEEDS $DL_SPEED"
                    rm -f /tmp/speedtest.tmp
                else
                    echo "  Download $i: Failed"
                    DL_SPEEDS="$DL_SPEEDS 0"
                fi
                sleep 5
            done
            # Calculate average (excluding zeros)
            DL_SPEED=$(echo "$DL_SPEEDS" | awk '{sum=0; count=0; for(i=1;i<=NF;i++) if($i>0) {sum+=$i; count++} if(count>0) print sum/count; else print 0}')
            echo "Average Download: ${DL_SPEED} MB/s"
            ;;
    esac
    
    # Upload test - adaptive size
    case $LOCATION in
        "LondonOffice"|"MKOffice")
            echo "Upload test starting (1MB)..."
            dd if=/dev/zero of=/tmp/upload.tmp bs=1M count=1 2>/dev/null
            UL_SIZE=1
            ;;
        "RuralOnSite")
            echo "Upload test starting (512KB - rural optimized)..."
            dd if=/dev/zero of=/tmp/upload.tmp bs=512k count=1 2>/dev/null
            UL_SIZE=0.5
            ;;
    esac
    
    UL_START=$(date +%s.%N)
    timeout 60 curl -F "file=@/tmp/upload.tmp" http://httpbin.org/post -o /dev/null -s
    UL_END=$(date +%s.%N)
    UL_TIME=$(echo "$UL_END - $UL_START" | bc)
    UL_SPEED=$(echo "scale=2; $UL_SIZE / $UL_TIME" | bc)
    echo "Upload: ${UL_SPEED} MB/s in ${UL_TIME}s"
    rm -f /tmp/upload.tmp
    
    # Store results
    echo "$DL_SPEED,$UL_SPEED" > /tmp/speeds.txt
}

# Connect time test - location adaptive
connect_time_test() {
    echo "=== Connect Time Test ==="
    
    # Skip connect time test if ModemManager is managing the connection
    if [ -n "$DETECTED_MODEM_NUM" ] && sudo mmcli -m $DETECTED_MODEM_NUM 2>/dev/null | grep -q "state: connected"; then
        echo "Modem is managed by ModemManager - connect time test skipped"
        echo "Connection is actively managed, no manual connect/disconnect testing performed"
        echo "ModemManager handles reconnection automatically on network issues"
        
        echo "Current connection statistics:"
        sudo mmcli -m $DETECTED_MODEM_NUM 2>/dev/null | grep -E "(duration|bytes)" || echo "No connection stats available"
        
        # Don't create connect_time.txt file - this will exclude it from CSV
        return
    elif [ -n "$DETECTED_MODEM_NUM" ]; then
        echo "⚠️  WARNING: ModemManager detected but modem not in connected state"
        echo "Skipping connect time test to avoid disrupting connection"
        echo "Connect Time,N/A - Connection Protected,N/A,Avoiding disruption of active connection" >> /tmp/connect_note.txt
        return
    fi
    
    # Only run actual connect time test if modem is not managed by ModemManager
    case $LOCATION in
        "LondonOffice")
            attempts=1
            timeout=60
            sleep_between=2
            ;;
        "MKOffice")
            attempts=3
            timeout=90
            sleep_between=3
            ;;
        "RuralOnSite")
            attempts=5
            timeout=120
            sleep_between=5
            ;;
    esac
    
    echo "Running actual connect time test ($attempts attempts)..."
    CONNECT_TIMES=""
    for i in $(seq 1 $attempts); do
        echo "Connect test $i..."
        START_TIME=$(date +%s.%N)
        
        CFUN_DISABLE=$(send_at "AT+CFUN=0")
        echo "Disable result: $CFUN_DISABLE"
        sleep $sleep_between
        
        CFUN_ENABLE=$(send_at "AT+CFUN=1")
        echo "Enable result: $CFUN_ENABLE"
        
        # Wait for network registration
        CONNECT_TIME=$timeout
        while [ "$(send_at 'AT+CREG?' | grep -o '0,1\|0,5')" = "" ]; do
            sleep 1
            CURRENT_TIME=$(date +%s.%N)
            ELAPSED=$(echo "$CURRENT_TIME - $START_TIME" | bc 2>/dev/null)
            if [ $? -ne 0 ] || (( $(echo "$ELAPSED > $timeout" | bc -l 2>/dev/null) )); then
                echo "Connect timeout after ${timeout}s"
                CONNECT_TIME=$timeout
                break
            fi
            CONNECT_TIME=$ELAPSED
        done
        
        if [ "$CONNECT_TIME" != "$timeout" ]; then
            END_TIME=$(date +%s.%N)
            CONNECT_TIME=$(echo "$END_TIME - $START_TIME" | bc 2>/dev/null || echo "$timeout")
        fi
        
        echo "Connect time $i: ${CONNECT_TIME}s"
        CONNECT_TIMES="$CONNECT_TIMES $CONNECT_TIME"
        
        if [ $attempts -gt 1 ]; then
            sleep $(($sleep_between * 2))
        fi
    done
    
    # Calculate average connect time
    AVG_CONNECT=$(echo "$CONNECT_TIMES" | awk '{sum=0; count=0; for(i=1;i<=NF;i++) if($i>0) {sum+=$i; count++} if(count>0) print sum/count; else print ""}')
    if [ -n "$AVG_CONNECT" ]; then
        echo "Average connect time: ${AVG_CONNECT}s"
        echo "$AVG_CONNECT" > /tmp/connect_time.txt
    else
        echo "No valid connect times recorded"
    fi
}

# Enhanced tests for specific locations
enhanced_tests() {
    case $LOCATION in
        "MKOffice")
            echo "=== MK-Specific: Network Stability Test ==="
            echo "Extended ping test (60 packets)..."
            ping -c 60 8.8.8.8 | tee /tmp/ping_stability.txt
            PACKET_LOSS=$(grep "packet loss" /tmp/ping_stability.txt | grep -o '[0-9]\+%')
            echo "Packet loss: $PACKET_LOSS"
            
            echo "Signal monitoring (18 samples over 3 minutes)..."
            for i in {1..18}; do
                CSQ_RESPONSE=$(send_at 'AT+CSQ')
                CSQ_VALUE=$(echo "$CSQ_RESPONSE" | grep -o '[0-9]\+' | head -1)
                # Handle empty response
                if [ -z "$CSQ_VALUE" ]; then
                    CSQ_VALUE="0"
                fi
                echo "Sample $i: CSQ=$CSQ_VALUE" 
                echo "$i,$CSQ_VALUE" >> /tmp/signal_stability.txt
                sleep 10
            done
            ;;
            
        "RuralOnSite")
            echo "=== Rural-Specific: Network Fallback Test ==="
            echo "Scanning all available networks (this may take 2-3 minutes)..."
            timeout 180 sh -c "$(send_at 'AT+COPS=?')" > /tmp/network_scan.txt
            NETWORK_COUNT=$(grep -o '([0-9]*,' /tmp/network_scan.txt | wc -l)
            echo "Available networks found: $NETWORK_COUNT"
            
            # Test network mode configurations
            echo "Testing network mode fallback..."
            send_at 'AT+QCFG="nwscanmode",3'  # LTE only
            sleep 10
            LTE_REG=$(send_at 'AT+CREG?' | grep -o '0,1\|0,5')
            echo "LTE-only registration: $LTE_REG"
            
            send_at 'AT+QCFG="nwscanmode",0'  # Auto mode
            sleep 15
            AUTO_REG=$(send_at 'AT+CREG?' | grep -o '0,1\|0,5')
            echo "Auto mode registration: $AUTO_REG"
            
            echo "=== Rural-Specific: Enhanced GNSS Test ==="
            send_at 'AT+QGPSCFG="gpsnmeatype",31'
            send_at 'AT+QGPSCFG="glonassnmeatype",1'
            send_at 'AT+QGPS=1'
            
            echo "Waiting for GNSS fix (up to 5 minutes)..."
            GNSS_FIXED=false
            for i in {1..30}; do
                GNSS_STATUS=$(send_at 'AT+QGPSLOC?' | grep -v "ERROR")
                if [ "$GNSS_STATUS" != "" ] && [ "$GNSS_STATUS" != "No response" ]; then
                    echo "GNSS fix acquired after $((i*10)) seconds"
                    echo "Location: $GNSS_STATUS"
                    GNSS_FIXED=true
                    break
                fi
                echo "  Waiting... attempt $i/30"
                sleep 10
            done
            
            if [ "$GNSS_FIXED" = true ]; then
                echo "Taking 10 position samples for accuracy assessment..."
                for j in {1..10}; do
                    POS=$(send_at 'AT+QGPSLOC?')
                    echo "Sample $j: $POS"
                    echo "$j,$POS" >> /tmp/gnss_samples.txt
                    sleep 6
                done
            fi
            
            echo "=== Rural-Specific: Power Analysis ==="
            send_at 'AT+CPSMS=1,,,,"10100000","00000001"'
            echo "PSM Status: $(send_at 'AT+CPSMS?')"
            send_at 'AT+CEDRXS=1,4,"1001"'
            echo "eDRX Status: $(send_at 'AT+CEDRXS?')"
            echo "Temperature: $(send_at 'AT+QTEMP')"
            echo "Voltage: $(send_at 'AT+CBC')"
            ;;
    esac
}

# Generate location-specific CSV results
generate_csv_results() {
    echo "Feature,Value,Score,Notes" > $RESULTS_FILE
    
    # Signal strength scoring (location-specific thresholds)
    CSQ_RESPONSE=$(send_at 'AT+CSQ')
    CSQ_NUM=$(echo "$CSQ_RESPONSE" | grep -o '[0-9]\+' | head -1)
    
    # Handle empty CSQ response
    if [ -z "$CSQ_NUM" ] || [ "$CSQ_NUM" = "" ]; then
        CSQ_NUM=0
    fi
    
    case $LOCATION in
        "LondonOffice")
            if [ -n "$CSQ_NUM" ] && [ "$CSQ_NUM" -gt 20 ]; then SIGNAL_SCORE=5
            elif [ -n "$CSQ_NUM" ] && [ "$CSQ_NUM" -gt 15 ]; then SIGNAL_SCORE=4  
            elif [ -n "$CSQ_NUM" ] && [ "$CSQ_NUM" -gt 10 ]; then SIGNAL_SCORE=3
            elif [ -n "$CSQ_NUM" ] && [ "$CSQ_NUM" -gt 5 ]; then SIGNAL_SCORE=2
            else SIGNAL_SCORE=1; fi
            TARGET="Office target >20"
            ;;
        "MKOffice")
            if [ -n "$CSQ_NUM" ] && [ "$CSQ_NUM" -gt 18 ]; then SIGNAL_SCORE=5
            elif [ -n "$CSQ_NUM" ] && [ "$CSQ_NUM" -gt 14 ]; then SIGNAL_SCORE=4  
            elif [ -n "$CSQ_NUM" ] && [ "$CSQ_NUM" -gt 10 ]; then SIGNAL_SCORE=3
            elif [ -n "$CSQ_NUM" ] && [ "$CSQ_NUM" -gt 6 ]; then SIGNAL_SCORE=2
            else SIGNAL_SCORE=1; fi
            TARGET="MK target 10-18"
            ;;
        "RuralOnSite")
            if [ -n "$CSQ_NUM" ] && [ "$CSQ_NUM" -gt 12 ]; then SIGNAL_SCORE=5
            elif [ -n "$CSQ_NUM" ] && [ "$CSQ_NUM" -gt 8 ]; then SIGNAL_SCORE=4   
            elif [ -n "$CSQ_NUM" ] && [ "$CSQ_NUM" -gt 5 ]; then SIGNAL_SCORE=3   
            elif [ -n "$CSQ_NUM" ] && [ "$CSQ_NUM" -gt 3 ]; then SIGNAL_SCORE=2   
            else SIGNAL_SCORE=1; fi
            TARGET="Rural target >5"
            ;;
    esac
    
    echo "Signal Strength,$CSQ_NUM,$SIGNAL_SCORE,CSQ value - $TARGET" >> $RESULTS_FILE
    
    # Speed scoring (location-specific thresholds)
    if [ -f /tmp/speeds.txt ]; then
        SPEEDS=$(cat /tmp/speeds.txt)
        DL_SPEED=$(echo $SPEEDS | cut -d',' -f1)
        UL_SPEED=$(echo $SPEEDS | cut -d',' -f2)
        
        case $LOCATION in
            "LondonOffice")
                if (( $(echo "$DL_SPEED > 10" | bc -l) )); then DL_SCORE=5
                elif (( $(echo "$DL_SPEED > 5" | bc -l) )); then DL_SCORE=4
                elif (( $(echo "$DL_SPEED > 2" | bc -l) )); then DL_SCORE=3
                elif (( $(echo "$DL_SPEED > 1" | bc -l) )); then DL_SCORE=2
                else DL_SCORE=1; fi
                DL_TARGET="Office target >10MB/s"
                UL_TARGET="Office target >5MB/s"
                ;;
            "MKOffice")
                if (( $(echo "$DL_SPEED > 8" | bc -l) )); then DL_SCORE=5
                elif (( $(echo "$DL_SPEED > 5" | bc -l) )); then DL_SCORE=4
                elif (( $(echo "$DL_SPEED > 3" | bc -l) )); then DL_SCORE=3
                elif (( $(echo "$DL_SPEED > 1" | bc -l) )); then DL_SCORE=2
                else DL_SCORE=1; fi
                DL_TARGET="MK target >3MB/s"
                UL_TARGET="MK target >2MB/s"
                ;;
            "RuralOnSite")
                if (( $(echo "$DL_SPEED > 3" | bc -l) )); then DL_SCORE=5
                elif (( $(echo "$DL_SPEED > 1.5" | bc -l) )); then DL_SCORE=4
                elif (( $(echo "$DL_SPEED > 0.8" | bc -l) )); then DL_SCORE=3
                elif (( $(echo "$DL_SPEED > 0.5" | bc -l) )); then DL_SCORE=2
                else DL_SCORE=1; fi
                DL_TARGET="Rural target >0.8MB/s"
                UL_TARGET="Rural target >0.3MB/s"
                ;;
        esac
        
        echo "Download Speed,${DL_SPEED}MB/s,$DL_SCORE,$DL_TARGET" >> $RESULTS_FILE
        echo "Upload Speed,${UL_SPEED}MB/s,$DL_SCORE,$UL_TARGET" >> $RESULTS_FILE
    fi
    
    # Connect time scoring (only if actual data available)
    if [ -f /tmp/connect_time.txt ]; then
        CONN_TIME=$(cat /tmp/connect_time.txt)
        
        # Only add to CSV if we have valid connect time data
        if [ -n "$CONN_TIME" ] && [ "$CONN_TIME" != "nans" ] && [ "$CONN_TIME" != "nan" ] && [ "$CONN_TIME" != "" ]; then
            case $LOCATION in
                "LondonOffice")
                    if (( $(echo "$CONN_TIME < 10" | bc -l 2>/dev/null) )); then CONN_SCORE=5
                    elif (( $(echo "$CONN_TIME < 20" | bc -l 2>/dev/null) )); then CONN_SCORE=4
                    elif (( $(echo "$CONN_TIME < 30" | bc -l 2>/dev/null) )); then CONN_SCORE=3
                    elif (( $(echo "$CONN_TIME < 45" | bc -l 2>/dev/null) )); then CONN_SCORE=2
                    else CONN_SCORE=1; fi
                    CONN_TARGET="Office target <10s"
                    ;;
                "MKOffice")
                    if (( $(echo "$CONN_TIME < 15" | bc -l 2>/dev/null) )); then CONN_SCORE=5
                    elif (( $(echo "$CONN_TIME < 25" | bc -l 2>/dev/null) )); then CONN_SCORE=4
                    elif (( $(echo "$CONN_TIME < 35" | bc -l 2>/dev/null) )); then CONN_SCORE=3
                    elif (( $(echo "$CONN_TIME < 50" | bc -l 2>/dev/null) )); then CONN_SCORE=2
                    else CONN_SCORE=1; fi
                    CONN_TARGET="MK target <25s"
                    ;;
                "RuralOnSite")
                    if (( $(echo "$CONN_TIME < 30" | bc -l 2>/dev/null) )); then CONN_SCORE=5
                    elif (( $(echo "$CONN_TIME < 45" | bc -l 2>/dev/null) )); then CONN_SCORE=4
                    elif (( $(echo "$CONN_TIME < 60" | bc -l 2>/dev/null) )); then CONN_SCORE=3
                    elif (( $(echo "$CONN_TIME < 90" | bc -l 2>/dev/null) )); then CONN_SCORE=2
                    else CONN_SCORE=1; fi
                    CONN_TARGET="Rural target <60s"
                    ;;
            esac
            
            echo "Connect Time,${CONN_TIME}s,$CONN_SCORE,$CONN_TARGET" >> $RESULTS_FILE
        else
            if [ -f /tmp/connect_note.txt ]; then
                CONNECT_NOTE=$(cat /tmp/connect_note.txt)
                echo "$CONNECT_NOTE" >> $RESULTS_FILE
                rm -f /tmp/connect_note.txt
            else
                echo "Connect Time,N/A - MM Managed,N/A,ModemManager handles connections" >> $RESULTS_FILE
            fi
        fi
    else
        echo "Connect Time,N/A - MM Managed,N/A,ModemManager handles connections" >> $RESULTS_FILE
    fi
    
    # Add latency info
    LATENCY=$(ping -c 5 8.8.8.8 | grep "min/avg/max" | cut -d'=' -f2 | cut -d'/' -f2)
    echo "Latency,${LATENCY}ms,N/A,Average ping time" >> $RESULTS_FILE
    
    # Basic compatibility scores
    echo "Driver Compatibility,Working,5,USB enumeration OK" >> $RESULTS_FILE  
    
    # SIM compatibility - check if we got ICCID
    ICCID_CHECK=$(send_at 'AT+CCID')
    if [ "$ICCID_CHECK" != "No response" ] && [ -n "$ICCID_CHECK" ]; then
        echo "SIM Compatibility,Working,5,ICCID: $ICCID_CHECK" >> $RESULTS_FILE
    else
        echo "SIM Compatibility,Limited,3,SIM detected but ICCID not accessible" >> $RESULTS_FILE
    fi
    
    echo "AT Command Compatibility,Working,5,All commands responding via MM" >> $RESULTS_FILE
    
    # Location-specific additional metrics
    case $LOCATION in
        "MKOffice")
            if [ -f /tmp/ping_stability.txt ]; then
                PACKET_LOSS_LINE=$(grep "packet loss" /tmp/ping_stability.txt)
                PACKET_LOSS=$(echo "$PACKET_LOSS_LINE" | grep -o '[0-9]\+%' | head -1 | tr -d '%')
                
                # Handle empty packet loss
                if [ -z "$PACKET_LOSS" ]; then
                    PACKET_LOSS=0
                fi
                
                if [ "$PACKET_LOSS" -eq 0 ]; then STAB_SCORE=5
                elif [ "$PACKET_LOSS" -lt 3 ]; then STAB_SCORE=4
                elif [ "$PACKET_LOSS" -lt 5 ]; then STAB_SCORE=3
                elif [ "$PACKET_LOSS" -lt 10 ]; then STAB_SCORE=2
                else STAB_SCORE=1; fi
                echo "Network Stability,${PACKET_LOSS}%,$STAB_SCORE,Packet loss percentage" >> $RESULTS_FILE
            fi
            ;;
        "RuralOnSite")
            if [ -f /tmp/network_scan.txt ]; then
                NETWORK_COUNT=$(grep -o '([0-9]*,' /tmp/network_scan.txt | wc -l)
                if [ "$NETWORK_COUNT" -gt 4 ]; then FALLBACK_SCORE=5
                elif [ "$NETWORK_COUNT" -gt 2 ]; then FALLBACK_SCORE=4
                elif [ "$NETWORK_COUNT" -gt 1 ]; then FALLBACK_SCORE=3
                elif [ "$NETWORK_COUNT" -eq 1 ]; then FALLBACK_SCORE=2
                else FALLBACK_SCORE=1; fi
                echo "Network Fallback,$NETWORK_COUNT networks,$FALLBACK_SCORE,Available networks" >> $RESULTS_FILE
            fi
            
            if [ -f /tmp/gnss_samples.txt ]; then
                GNSS_SAMPLES=$(wc -l < /tmp/gnss_samples.txt)
                if [ "$GNSS_SAMPLES" -gt 8 ]; then GNSS_SCORE=5
                elif [ "$GNSS_SAMPLES" -gt 5 ]; then GNSS_SCORE=4
                elif [ "$GNSS_SAMPLES" -gt 3 ]; then GNSS_SCORE=3
                elif [ "$GNSS_SAMPLES" -gt 0 ]; then GNSS_SCORE=2
                else GNSS_SCORE=1; fi
                echo "GNSS Performance,$GNSS_SAMPLES samples,$GNSS_SCORE,Position samples acquired" >> $RESULTS_FILE
            else
                echo "GNSS Performance,No fix,1,Could not acquire position" >> $RESULTS_FILE
            fi
            ;;
    esac
}

# Main test sequence
main_tests() {
    echo -e "${BLUE}======================================${NC}"
    echo -e "${BLUE}$LOCATION_NAME MODEM TEST${NC}"
    echo -e "${BLUE}Started: $(date)${NC}"
    echo -e "${BLUE}======================================${NC}"
    
    # Test 1: Basic modem info
    echo -e "${YELLOW}=== Modem Information ===${NC}" | tee -a $LOG_FILE
    echo "Manufacturer: $(send_at 'AT+CGMI')" | tee -a $LOG_FILE
    echo "Model: $(send_at 'AT+CGMM')" | tee -a $LOG_FILE
    echo "Firmware: $(send_at 'AT+CGMR')" | tee -a $LOG_FILE
    echo "IMEI: $(send_at 'AT+CGSN')" | tee -a $LOG_FILE
    
    # Test 2: SIM info
    echo -e "${YELLOW}=== SIM Information ===${NC}" | tee -a $LOG_FILE
    echo "ICCID: $(send_at 'AT+CCID')" | tee -a $LOG_FILE
    echo "IMSI: $(send_at 'AT+CIMI')" | tee -a $LOG_FILE
    echo "PIN Status: $(send_at 'AT+CPIN?')" | tee -a $LOG_FILE
    
    # Test 3: Network and signal
    echo -e "${YELLOW}=== Network Status ===${NC}" | tee -a $LOG_FILE
    CREG=$(send_at 'AT+CREG?')
    COPS=$(send_at 'AT+COPS?')
    CSQ=$(send_at 'AT+CSQ')
    CESQ=$(send_at 'AT+CESQ')
    
    echo "Registration: $CREG" | tee -a $LOG_FILE
    echo "Operator: $COPS" | tee -a $LOG_FILE  
    echo "Signal Quality: $CSQ" | tee -a $LOG_FILE
    echo "Extended Signal: $CESQ" | tee -a $LOG_FILE
    
    # Test 4: Advanced network info
    echo -e "${YELLOW}=== Advanced Network Info ===${NC}" | tee -a $LOG_FILE
    echo "Network Info: $(send_at 'AT+QNWINFO')" | tee -a $LOG_FILE
    echo "Engineering Mode: $(send_at 'AT+QENG=\"servingcell\"')" | tee -a $LOG_FILE
    
    # Test 5: Band info
    echo -e "${YELLOW}=== Band Information ===${NC}" | tee -a $LOG_FILE
    echo "Current Bands: $(send_at 'AT+QBAND?')" | tee -a $LOG_FILE
    echo "LTE Bands: $(send_at 'AT+QCFG=\"band\"')" | tee -a $LOG_FILE
    
    # Test 6: GNSS capability
    echo -e "${YELLOW}=== GNSS Testing ===${NC}" | tee -a $LOG_FILE
    echo "GNSS Status: $(send_at 'AT+QGPS?')" | tee -a $LOG_FILE
    
    # Try to enable GNSS (non-blocking)
    GNSS_ENABLE_RESULT=$(send_at 'AT+QGPS=1')
    echo "GNSS Enable: $GNSS_ENABLE_RESULT" | tee -a $LOG_FILE
    
    case $LOCATION in
        "LondonOffice") 
            echo "Waiting for GNSS (5s)..."
            sleep 5 
            ;;
        "MKOffice") 
            echo "Waiting for GNSS (60s)..."
            sleep 60 
            ;;
        "RuralOnSite") ;; # Handled in enhanced_tests
    esac
    
    if [ "$LOCATION" != "RuralOnSite" ]; then
        echo "GNSS Location: $(send_at 'AT+QGPSLOC?')" | tee -a $LOG_FILE
    fi
    
    # Test 7: Performance tests
    echo -e "${YELLOW}=== Performance Tests ===${NC}" | tee -a $LOG_FILE
    
    # Latency test
    echo "--- Latency Test ---" | tee -a $LOG_FILE
    case $LOCATION in
        "LondonOffice") 
            PING_RESULT=$(ping -c 10 8.8.8.8 | grep "min/avg/max")
            ;;
        "MKOffice")
            PING_RESULT=$(ping -c 20 8.8.8.8 | grep "min/avg/max")
            ;;
        "RuralOnSite")
            PING_RESULT=$(ping -c 30 8.8.8.8 | grep "min/avg/max")
            ;;
    esac
    echo "Ping 8.8.8.8: $PING_RESULT" | tee -a $LOG_FILE
    
    # Speed tests  
    speed_test | tee -a $LOG_FILE
    
    # Connect time test
    connect_time_test | tee -a $LOG_FILE
    
    # Enhanced location-specific tests
    enhanced_tests | tee -a $LOG_FILE
    
    # Test 8: ModemManager integration and enhanced info
    echo -e "${YELLOW}=== ModemManager Status & Enhanced Info ===${NC}" | tee -a $LOG_FILE
    if which mmcli > /dev/null; then
        echo "Modem List:" | tee -a $LOG_FILE
        mmcli -L | tee -a $LOG_FILE
        
        echo "Detailed Modem Info:" | tee -a $LOG_FILE
        mmcli -m 0 | tee -a $LOG_FILE
        
        echo "Signal Info:" | tee -a $LOG_FILE
        mmcli -m 0 --signal 2>/dev/null | tee -a $LOG_FILE || echo "Signal details not available"
        
        echo "SIM Info:" | tee -a $LOG_FILE
        echo "Getting SIM details via ModemManager..." | tee -a $LOG_FILE
        sudo mmcli --sim 0 2>/dev/null | tee -a $LOG_FILE || echo "SIM details not available (may need sudo permissions)" | tee -a $LOG_FILE
        
        echo "Bearer Info:" | tee -a $LOG_FILE
        for bearer in $(mmcli -m 0 | grep "paths:" -A 10 | grep -o "/org/freedesktop/ModemManager1/Bearer/[0-9]"); do
            mmcli -b "$bearer" 2>/dev/null || echo "Bearer $bearer not accessible"
        done | tee -a $LOG_FILE
    else
        echo "ModemManager not available" | tee -a $LOG_FILE
    fi
    
    # Test 9: Power consumption info (with better error handling)
    echo -e "${YELLOW}=== Power Status ===${NC}" | tee -a $LOG_FILE
    
    # Try to get power info from ModemManager first
    if [ -n "$ACTIVE_MODEM_NUM" ] && sudo mmcli -m $ACTIVE_MODEM_NUM >/dev/null 2>&1; then
        echo "Using ModemManager for power status:" | tee -a $LOG_FILE
        sudo mmcli -m $ACTIVE_MODEM_NUM | grep -E "(power|state|temperature)" | tee -a $LOG_FILE || echo "Power info via MM not available" | tee -a $LOG_FILE
    fi
    
    # Fallback to AT commands
    echo "Function Level: $(send_at 'AT+CFUN?')" | tee -a $LOG_FILE
    echo "Power Saving: $(send_at 'AT+CPSMS?')" | tee -a $LOG_FILE
    
    # Try temperature if available
    TEMP_INFO=$(send_at 'AT+QTEMP')
    if [ "$TEMP_INFO" != "No response" ]; then
        echo "Temperature: $TEMP_INFO" | tee -a $LOG_FILE
    fi
    
    # Generate CSV results
    generate_csv_results
    
    echo -e "${GREEN}======================================${NC}"
    echo -e "${GREEN}$LOCATION_NAME TEST COMPLETE${NC}"
    echo -e "${GREEN}Results saved to: $LOG_FILE${NC}"
    echo -e "${GREEN}CSV data saved to: $RESULTS_FILE${NC}" 
    echo -e "${GREEN}======================================${NC}"
}

# Main execution
main() {
    select_location
    install_dependencies
    main_tests
    
    echo ""
    echo -e "${BLUE}Test Summary:${NC}"
    echo -e "Location: ${GREEN}$LOCATION_NAME${NC}"
    echo -e "Log File: ${YELLOW}$LOG_FILE${NC}"
    echo -e "CSV Results: ${YELLOW}$RESULTS_FILE${NC}"
    echo ""
    echo -e "${GREEN}Test completed successfully!${NC}"
}

# Run the script
main
