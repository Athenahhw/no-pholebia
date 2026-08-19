## Technical Architecture: Multi-Modal Detection Engine

The detection module (`ScanScreen`) employs a highly optimised, multi-modal sensor fusion approach. It leverages both edge computing and cloud-based AI to ensure real-time performance whilst maintaining a completely fluid user interface on mobile devices.

### 1. Stream-Only Visual Processing Pipeline
To prevent hardware conflicts and UI stutter (jank) typically caused by camera shutter APIs, the system operates on a pure stream-based architecture.
* **In-Memory Frame Conversion:** It captures a continuous YUV420 image stream directly from the native camera and performs low-level pixel conversion to RGB in-memory.
* **Asynchronous Task Allocation:**
  * **High-Frequency Routine:** Glint tracking algorithms process every viable frame to continuously map candidates and compute accurate optical flicker scores.
  * **Low-Frequency Routine:** Heavy ML Kit object detection is strictly governed by an asynchronous processing lock (`_objectDetectCallInFlight`), guaranteeing that the main UI thread remains unblocked and the camera preview stays completely smooth.

### 2. Motion Stability & Anti-Shake Mechanism
As optical tracking is highly sensitive to motion blur, the system implements a hardware-level stabilisation protocol to ensure data integrity.
* **Accelerometer Monitoring:** Integrates the `sensors_plus` library to continuously evaluate the device's three-axis acceleration vector.
* **Dynamic State Reset:** If user movement exceeds the predefined tolerance threshold (acceleration > 8.0), the system categorises the state as excessive shake. It immediately intercepts the scanning process, flushes polluted bounding boxes, clears invalid glint histories, and resets the 6-second timer. This strict validation ensures only high-quality, stable telemetry is forwarded for AI analysis.

### 3. Concurrent Sensor Fusion
Whilst the optical scan is actively running, the application conducts asynchronous electromagnetic sniffing in the background.
* **Non-Blocking Network Scans:** Wi-Fi port scanning and Bluetooth Low Energy (BLE) device discovery are executed as concurrent Futures. This multi-dimensional approach dramatically reduces false-positive rates by correlating visual anomalies with suspicious wireless traffic.

### 4. Edge-to-Cloud Synchronisation
* **Payload Assembly:** Upon a successful and stable 6-second window, all edge-computed metrics—including high-risk flicker scores, detected bounding boxes, ambient brightness shifts, and intercepted network devices—are compiled into a structured `DetectionSessionSummary`.
* **Backend Offloading:** This lightweight payload, accompanied by a compressed reference frame, is then dispatched to the Python/FastAPI backend. Here, the heavy lifting of semantic reasoning and risk assessment is handed over to the cloud-based LLM engine.
