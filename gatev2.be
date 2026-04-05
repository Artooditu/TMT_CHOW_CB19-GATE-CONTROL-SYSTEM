import mqtt
import string

class Gate : Driver
  # --------------------------------------------------
  # Configuration
  # --------------------------------------------------

  # Base MQTT topic
  # Change this to make topics unique in your MQTT setup
  var topic_base

  # --------------------------------------------------
  # Runtime state
  # --------------------------------------------------

  # Serial interface
  var ser

  # When true, keep polling READ STATUS every second
  var readStatus

  # High-level gate state for HA cover
  # closed / open / opening / closing / stopped
  var state

  # Numeric reported position
  var position

  # Resting position class
  # closed / ped / partial / open
  var mode

  # Current action / movement intent
  # "Opening to Full"
  # "Opening to Ped"
  # "Closing"
  # "Stopped"
  var action

  # --------------------------------------------------
  # init()
  # --------------------------------------------------
  def init()
    # ===== MQTT topic base =====
    self.topic_base = "tasmota_gate_new"

    # ===== Initial runtime state =====
    self.readStatus = false
    self.state = "closed"
    self.position = 0
    self.mode = "closed"
    self.action = "Stopped"

    # ===== Serial port =====
    # Working configuration:
    # TX = GPIO17
    # RX = GPIO16
    # baud = 9600
    # format = 8N1
    self.ser = serial(17, 16, 9600, serial.SERIAL_8N1)

    # Register driver
    tasmota.add_driver(self)

    # Re-subscribe after MQTT reconnect
    tasmota.add_rule("mqtt#connected", /->self.on_mqtt_connected())

    # Initial MQTT setup
    self.setup_mqtt_state()
  end

  # --------------------------------------------------
  # MQTT topic helper
  # --------------------------------------------------
  def tp(suffix)
    return self.topic_base + "/" + suffix
  end

  # --------------------------------------------------
  # Shared MQTT setup
  # --------------------------------------------------
  def setup_mqtt_state()
    self.subscribe()
    mqtt.publish(self.tp("availability"), "online")
    self.request_status()
  end

  # --------------------------------------------------
  # MQTT reconnect callback
  # --------------------------------------------------
  def on_mqtt_connected()
    self.setup_mqtt_state()
  end

  # --------------------------------------------------
  # Cleanup
  # --------------------------------------------------
  def remove()
    mqtt.publish(self.tp("availability"), "offline")
    tasmota.remove_driver(self)
  end

  # --------------------------------------------------
  # MQTT subscriptions
  # --------------------------------------------------
  def subscribe()
    mqtt.subscribe(self.tp("cmd"))
    print("connected MQTT")
  end

  # --------------------------------------------------
  # Handle MQTT commands
  #
  # Send to:
  #   <topic_base>/cmd
  #
  # Payloads:
  #   OPEN
  #   CLOSE
  #   STOP
  #   PED_OPEN
  #   STATUS
  #   READ_FUNCTION
  #   READ_DEVINFO
  #
  # Serial commands are kept aligned with the existing
  # gate protocol such as FULL OPEN, FULL CLOSE,
  # PED OPEN, READ FUNCTION, READ DEVINFO, STOP [1]
  # --------------------------------------------------
  def mqtt_data(topic, idx, payload_s, payload_b)
    if topic != self.tp("cmd")
      return false
    end

    var command = payload_s

    if command == "OPEN"
      self.send_cmd("FULL OPEN;src=P0004A83\r\n")
      return true
    end

    if command == "CLOSE"
      self.send_cmd("FULL CLOSE;src=P0004A83\r\n")
      return true
    end

    if command == "STOP"
      self.send_cmd("STOP;src=P0004A83\r\n")
      return true
    end

    if command == "PED_OPEN"
      self.send_cmd("PED OPEN;src=P0004A83\r\n")
      return true
    end

    if command == "STATUS"
      self.request_status()
      return true
    end

    if command == "READ_FUNCTION"
      self.send_cmd("READ FUNCTION;src=P0004A83\r\n")
      return true
    end

    if command == "READ_DEVINFO"
      self.send_cmd("READ DEVINFO;src=P0004A83\r\n")
      return true
    end

    return false
  end

  # --------------------------------------------------
  # Send raw serial command
  # Also publish last command for debugging
  # --------------------------------------------------
  def send_cmd(cmd)
    mqtt.publish(self.tp("last_cmd"), cmd)
    self.ser.write(bytes().fromstring(cmd))
  end

  # --------------------------------------------------
  # Ask controller for current status
  # The original script repeatedly sends:
  # READ STATUS;src=P0004A83\r\n [1]
  # --------------------------------------------------
  def request_status()
    self.send_cmd("READ STATUS;src=P0004A83\r\n")
  end

  # --------------------------------------------------
  # Publish all normalized MQTT state
  # --------------------------------------------------
  def publish_all()
    mqtt.publish(self.tp("state"), self.state)
    mqtt.publish(self.tp("position"), str(self.position))
    mqtt.publish(self.tp("mode"), self.mode)
    mqtt.publish(self.tp("action"), self.action)
  end

  # --------------------------------------------------
  # Position -> resting mode
  #
  # Important:
  # mode is for resting classification only:
  #   closed / ped / partial / open
  # --------------------------------------------------
  def classify_mode(pos)
    if pos <= 0
      return "closed"
    end
    if pos == 25
      return "ped"
    end
    if pos >= 95
      return "open"
    end
    return "partial"
  end

  # --------------------------------------------------
  # Helper to update resting state
  # --------------------------------------------------
  def set_state(newstate, pos)
    self.state = newstate
    self.position = pos
    self.mode = self.classify_mode(pos)
    self.publish_all()
  end

  # --------------------------------------------------
  # Parse ACK STATUS payload
  #
  # Examples:
  #   FULL OPENING,28
  #   PED OPENING,22
  #   FULL CLOSING,34
  #   FULL CLOSED,0
  #   FULL OPENED,96
  #   DUAL STOPPED,35
  #   SINGLE STOPPED,20
  # --------------------------------------------------
  def processStatus(msg)
    var parts = string.split(msg, ",")
    if parts.size() < 2
      return
    end

    var status = parts[0]
    var pos = int(parts[1])

    # Opening toward full open
    if status == "FULL OPENING"
      self.readStatus = true
      self.state = "opening"
      self.position = pos
      self.mode = self.classify_mode(pos)
      self.action = "Opening to Full"
      self.publish_all()
      return
    end

    # Opening toward pedestrian position
    if status == "PED OPENING"
      self.readStatus = true
      self.state = "opening"
      self.position = pos
      self.mode = "ped"
      self.action = "Opening to Ped"
      self.publish_all()
      return
    end

    # Closing from any non-closed position
    if status == "FULL CLOSING"
      self.readStatus = true
      self.state = "closing"
      self.position = pos
      self.mode = self.classify_mode(pos)
      self.action = "Closing"
      self.publish_all()
      return
    end

    # In case PED CLOSING is reported explicitly
    if status == "PED CLOSING"
      self.readStatus = true
      self.state = "closing"
      self.position = pos
      self.mode = self.classify_mode(pos)
      self.action = "Closing"
      self.publish_all()
      return
    end

    # Fully closed final state
    if status == "FULL CLOSED"
      self.readStatus = false
      self.state = "closed"
      self.position = 0
      self.mode = "closed"
      self.action = "Stopped"
      self.publish_all()
      return
    end

    # Fully open final state
    if status == "FULL OPENED"
      self.readStatus = false
      self.state = "open"
      self.position = pos
      self.mode = "open"
      self.action = "Stopped"
      self.publish_all()
      return
    end

    # Stopped during full movement
    if status == "DUAL STOPPED"
      self.readStatus = false
      self.state = "stopped"
      self.position = pos
      self.mode = self.classify_mode(pos)
      self.action = "Stopped"
      self.publish_all()
      return
    end

    # Stopped during pedestrian movement
    if status == "SINGLE STOPPED"
      self.readStatus = false

      if pos == 25
        self.state = "open"
        self.position = pos
        self.mode = "ped"
      else
        self.state = "stopped"
        self.position = pos
        self.mode = self.classify_mode(pos)
      end

      self.action = "Stopped"
      self.publish_all()
      return
    end
  end

  # --------------------------------------------------
  # Parse board event message
  # Example:
  #   $V1PKF0,22,Opening;src=P0004A83
  #
  # These messages are used mainly to keep polling active
  # --------------------------------------------------
  def processMain(mainmsg)
    if mainmsg == "PedOpening"
      self.readStatus = true
      return
    end
    if mainmsg == "PedClosing"
      self.readStatus = true
      return
    end
    if mainmsg == "Opening"
      self.readStatus = true
      return
    end
    if mainmsg == "Closing"
      self.readStatus = true
      return
    end
    if mainmsg == "Stopped"
      self.readStatus = true
      return
    end
  end

  # --------------------------------------------------
  # Parse one serial line
  # --------------------------------------------------
  def processLine(line)
    if line == ""
      return
    end

    # Publish raw serial line for debugging
    mqtt.publish(self.tp("serial"), line)

    # Handle ACK STATUS lines
    var parts = string.split(line, ":")
    if parts.size() == 2
      if parts[0] == "ACK STATUS"
        self.processStatus(parts[1])
        return
      end
    end

    # Handle board event lines like:
    # $V1PKF0,22,Opening;src=P0004A83
    parts = string.split(line, ";")
    if parts.size() == 2
      var msgparts = string.split(parts[0], ",")
      if msgparts.size() == 3
        self.processMain(msgparts[2])
      end
    end
  end

  # --------------------------------------------------
  # Parse serial chunk
  #
  # The v1 of the reworked script split on "\r" and skipped the
  # last trailing empty part by looping to size()-2 [1]
  # --------------------------------------------------
  def processMSG(msg)
    if msg == nil
      return
    end

    var text = msg.asstring()
    if text == ""
      return
    end

    var lines = string.split(text, "\r")

    if lines.size() < 2
      return
    end

    for i : 0..lines.size()-2
      self.processLine(lines[i])
    end
  end

  # --------------------------------------------------
  # Tasmota periodic callback
  # 1. Drain serial input
  # 2. Poll READ STATUS while active
  # --------------------------------------------------
  def every_second()
    while self.ser.available()
      var msg = self.ser.read()
      self.processMSG(msg)
    end

    if self.readStatus
      self.request_status()
    end
  end
end

var gate = Gate()