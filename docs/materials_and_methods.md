# Materials and Methods: Antenna Aligner Development

## 1. Mathematical Formulations & Citations

### A. Global Positioning (WGS84)
To translate Latitude, Longitude, and Altitude into a Cartesian space for distance calculation, the app uses the World Geodetic System 1984 (WGS84).

**Formulas:**
$$N(\phi) = \frac{a}{\sqrt{1 - e^2 \sin^2 \phi}}$$
$$X = (N(\phi) + h) \cos \phi \cos \lambda$$
$$Z = (N(\phi)(1 - e^2) + h) \sin \phi$$

*   **Parameter Justification ($a, e^2$):** These define the Earth's ellipsoidal shape, ensuring that GPS coordinates (measured in degrees) are accurately converted to meters for alignment logic.

**Citation:**
National Imagery and Mapping Agency. (2000). *Department of Defense World Geodetic System 1984* (NIMA TR8350.2).

---

### B. Geomagnetic Alignment (WMM)
The app calculates "True North" by adjusting the raw magnetometer reading with the local magnetic declination ($\delta$).

**Logic:**
The declination is retrieved via the Android `GeomagneticField` API, which implements the **World Magnetic Model (WMM)**.
*   **Parameter Justification ($t$):** We pass the current system time to the WMM to account for the secular variation of the magnetic poles (approx. 5-10 arcminutes per year).

**Citation:**
Chulliat, A., et al. (2020). *The World Magnetic Model 2020: Full Technical Report*. NOAA National Centers for Environmental Information.

---

### C. Orientation Dynamics (Quaternions)
ARCore rotation is managed using Hamilton's quaternions to avoid "Gimbal Lock" during steep antenna elevations.

**Equation (Composition):**
$$\mathbf{q}_{k} = \mathbf{q}_{k-1} \otimes \Delta \mathbf{q}$$

**Citation:**
Kuipers, J. B. (1999). *Quaternions and Rotation Sequences*. Princeton University Press.

---

### D. Pose Estimation (Extended Kalman Filter)
The EKF fuses high-rate VIO data with low-rate GNSS updates.

#### 1. Prediction (Time Update)
Predicts the next state $\mathbf{\hat{x}}_k$ based on movement deltas:
$$\mathbf{\hat{x}}_k = \mathbf{x}_{k-1} + \Delta \mathbf{p}$$
$$\mathbf{P}_k = \mathbf{P}_{k-1} + \mathbf{Q}$$

*   **Parameter $Q$ (Process Noise):** Set to $0.01m^2$. Justification: This represents the expected drift of the ARCore VIO over a single frame.

#### 2. Correction (Measurement Update)
Adjusts the estimate when a GNSS fix $\mathbf{z}_k$ is received:
$$\mathbf{y}_k = \mathbf{z}_k - \mathbf{H}\mathbf{\hat{x}}_k$$
$$\mathbf{K}_k = \mathbf{P}_k \mathbf{H}^T (\mathbf{H} \mathbf{P}_k \mathbf{H}^T + \mathbf{R})^{-1}$$
$$\mathbf{x}_k = \mathbf{\hat{x}}_k + \mathbf{K}_k \mathbf{y}_k$$

*   **Parameter $R$ (Measurement Noise):** Set to $2.0m^2$. Justification: Corresponds to the RMS error of a standard mobile GNSS receiver in urban environments.

**Citation:**
Simon, D. (2006). *Optimal State Estimation: Kalman, H Infinity, and Nonlinear Approaches*. John Wiley & Sons.
