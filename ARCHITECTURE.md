# No Pholebia — Architecture Document

## 1. Project Objectives

Develop an iOS/Android application based on the concept of Agentic AI to assist users in identifying disguised pinhole cameras in specific environments. The core lies not in simple one-off recognition, but in enabling the AI agent to autonomously plan verification steps:
Discover suspicious object → Determine low confidence → Autonomously decide the next step (change angle, change position, check network anomalies) → Draw conclusions by synthesising multiple streams of evidence.

## 2. Competition Category

Confirmed participation in the "Information Application Category" (or a similar category not bound to specific hardware vendors). We are **no longer restricted by the requirement to utilise AMD-related resources**. The technical direction remains unchanged, but the architecture is no longer tied to specific hardware requirements, thereby significantly increasing development flexibility.

## 3. Overall System Architecture Diagram

```text
┌─────────────────────────────────────────────────────────┐
│                     User (App UI)                       │
└───────────────┬─────────────────────────┬───────────────┘
                │                         │
        ┌───────▼────────┐        ┌───────▼────────┐
        │ Frontend (App) │        │Backend (Server)│
        └───────┬────────┘        └───────┬────────┘
                │                         │
   ┌────────────┼────────────┐    ┌───────┼──────────────┐
   │            │            │    │       │              │
┌──▼───┐   ┌────▼────┐  ┌────▼──┐┌▼───────▼──┐  ┌────────▼───────┐
│Glint │   │Risk     │  │GPS &  ││Multi-Modal│  │Incident Map DB/│
│Object│   │Assess   │  │Map UI ││LLM Engine │  │Knowledge Base  │
│Detect│   │(Weights)│  │       ││(Semantic) │  │                │
│★YOURS│   │         │  │       ││           │  │                │
└──┬───┘   └─────────┘  └───────┘└───────────┘  └────────────────┘
   │
   └─► Outputs DetectionSessionSummary (with screenshots) → Transmits to Backend for Reasoning
   ```

## 4. Glint Detection + On-Device Object Detection (lib/detection/)
### 4.1 Responsibility Boundaries
Input: Real-time camera frames (camera stream).
Output: After a complete scan, compiles data into a DetectionSessionSummary object and POSTs it to the backend.
This module is not responsible for drawing conclusions (it does not judge "reasonableness"). It solely focuses on evidence gathering: bounding candidate locations, measuring glint anomalies, and attaching screenshots. Semantic judgement is delegated to the backend multi-modal LLM.

### 4.2 Internal Workflow

```text
User taps "One-Tap Scan"
  │
  ▼
ScanScreen opens camera, measures ambient brightness → Auto-enables torch if too dark
  │
  ▼
During the fixed 6-second scan, two tasks run concurrently:
  ├─ Every frame: GlintDetector.detect() identifies glint candidate points
  │             → GlintTracker tracks the flicker pattern of the same bright point (whilst shaking)
  │             → A high flicker score indicates a higher probability of directional reflection from a lens.
  │
  └─ Every 1.5s: ObjectDetectorService (Google ML Kit) detects candidate locations on-device
                → Only provides bounding boxes + rough classification; no pinpoint recognition.
  │
  ▼
Scan auto-terminates after 6 seconds, compiling DetectionSessionSummary:
  - glints (List of glint points + flicker scores)
  - boundingBoxes (Candidate locations, rough classifications by ML Kit)
  - environmentContext (User-input context, e.g., "washroom")
  - screenshotBase64 (The final frame, JPEG base64 encoded, for backend LLM visual analysis)
  - Other metadata (Ambient brightness, torch status, scan duration)
  │
  ▼
POST to Backend AI (DetectionBackendClient.submitScan)
  │
  ▼
Backend returns risk assessment results → onScanComplete callback → Redirects to ResultPage

```
### 4.3 File List

| File | Description |
| --- | --- |
| `camera_service.dart` | Camera initialisation, torch control, differential capture (torch on/off). |
| `image_converter.dart` | Converts `CameraImage` (YUV420) to `img.Image`. |
| `glint_detector.dart` | Glint point detection (flood-fill blob detection) + ambient brightness measurement + `GlintTracker` (multi-frame flicker tracking). |
| `object_detector_service.dart` | On-device object detection (Google ML Kit), bounding candidate locations. |
| `detection_result.dart` | Data structure definitions; `DetectionSessionSummary.toJson()` formulates the JSON payload. |
| `detection_backend_client.dart` | POSTs scan results to the backend API and retrieves the risk assessment response. |
| `scan_screen.dart` | Main scanning UI, integrating all logic, featuring a four-corner scanning frame, scanning line animation, and haptic/audio alerts. |

## 5. Frontend-Backend Data Contract

The complete format and field descriptions for `DetectionSessionSummary.toJson()` are documented in `BACKEND_DATA_FORMAT.md` and the example file `example_detection_summary.json`. These have been provided to backend teammates as a reference for prompt design.

## 6. Technology Stack Overview

| Component | Selection |
| --- | --- |
| App Framework | Flutter (Dart) |
| Camera Control | `camera` package |
| On-Device Object Detection | `google_mlkit_object_detection` (on-device computing, no server required) |
| Image Processing | `image` package |
| Network Requests | `http` |
| Backend Communication | REST API (JSON, including base64 screenshots) |

## 7. Software-Only Strategy (Hardware Independent)

Glint detection operates entirely independently of external light sources or specialised hardware:

1. **Multi-Frame Motion Tracking as Core Mechanism**: Without external light sources, bright spots in a single frame are difficult to distinguish from ordinary reflective objects (nails, metal fittings, glossy paint). Judging by the flicker pattern of the same bright point whilst the user shakes the phone serves as a low-cost, highly effective distinguishing feature.
2. **Utilising Built-in Phone Lighting**: Autonomously assesses ambient brightness, automatically turning on the torch to aid glint detection if the environment is too dim.
3. **Object Detection Focuses on Bounding, Delegating Semantics to Backend**: The on-device ML Kit solely needs to draw bounding boxes for candidate positions. The actual judgement of "what this is and whether it makes sense" is handed over to the backend multi-modal LLM via screenshot analysis. The frontend does not need to train/fine-tune models locally, dramatically lowering development complexity and hardware reliance.
4. **Honest Presentation of Confidence**: The narrative focus of the demo is on "how the Agent utilises limited evidence for multi-step reasoning and guides user verification", rather than overclaiming to completely replace professional detection equipment.

```



