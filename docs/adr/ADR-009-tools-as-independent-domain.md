# ADR-009: Tools & Equipment as an Independent Domain Module

## Status
Accepted

## Context
In an automotive workshop ERP/CRM, physical items managed by the platform fall into two fundamentally distinct categories:
1. **Consumable Materials & Parts (`Inventory`)**: Oil, brake pads, filters, screws, gaskets. These items are tracked by quantity/SKU, purchased in bulk, reserved for work orders, and **consumed permanently** (their physical quantity decrements upon use, never returning to the workshop shelf).
2. **Reusable Assets & Equipment (`Tools`)**: Torque wrenches, multimeters, hydraulic lifts, engine hoists, diagnostic scanners, specialized pullers. These items are **identifiable assets** (tagged with asset/patrimony numbers or serial numbers), have a multi-year operational lifespan, are assigned to mechanics for temporary custody, require periodic calibration/inspection, and return to the workshop repository upon check-in.

Conflating reusable tools with consumable inventory leads to severe domain model pollution (e.g., attempting to decrement quantities for items that are not consumed, lacking custody check-in/check-out lifecycle, inability to model calibration certificates, precision tolerances, and maintenance schedules).

## Decision
We establish **`Tools` (`com.gomech.api.modules.tools`)** as a first-class, independent domain module within the GoMech Modular Monolith architecture, strictly separated from `Inventory`.

### Core Principles:
1. **Independent Lifecycle & Ownership**:
   - `Tools` owns its schema tables (`tools`, `tool_categories`, `tool_custody_logs`, `tool_usages`, `tool_transfers`, `tool_maintenances`).
   - Tools are unique physical assets identified by `asset_tag` (unique per tenant) or `serial_number`.
2. **Real-time Custody & Location Tracking**:
   - Every tool has an operational status (`AVAILABLE`, `IN_USE`, `IN_MAINTENANCE`, `IN_TRANSIT`, `DECOMMISSIONED`, `LOST`), an assigned unit/branch, a physical shelf location, and an optional mechanic custodian (`current_holder_user_id`).
   - Every change of custody generates an immutable audit entry in `tool_custody_logs` with event types (`CHECK_OUT`, `CHECK_IN`, `ASSIGN`, `TRANSFER`, `RETURN`).
3. **Work Order Integration via Contracts**:
   - The `Operations` module links tool usage to active work orders exclusively through the public `ToolsContract` interface.
   - Using a tool on a work order changes its status to `IN_USE` and records custody without decreasing asset inventory.
4. **Preventive Maintenance & Metrological Calibration**:
   - Specialized tools (e.g., torque wrenches, pressure gauges) can require calibration cycles (`requires_calibration = true`, `default_maintenance_interval_days`).
   - The module tracks scheduled and performed maintenance logs, costs, calibration reports, and next due dates.
5. **Multi-Branch Transfers**:
   - Inter-unit tool transfers are supported with `TRFT-XXXXX` transfer numbers, origin dispatch, and destination receipt confirmation.

## Alternatives Considered
- **Treating Tools as Non-Consumable Products in Inventory**: Rejected because inventory data structures (batches, SKU stock balances, FIFO/average costing) do not support individual asset tags, mechanic check-out/check-in custody logs, and calibration cycles.
- **Generic Asset Management System**: Rejected to maintain tight integration with the automotive workflow (work orders, mechanics, multi-branch operations).

## Consequences
- **Positive**:
  - Clean separation of concerns between consumables and fixed assets.
  - Complete auditable history of who had which tool, when, on which work order, and when it was returned.
  - Compliance with quality assurance standards requiring calibrated measuring instruments.
  - Zero coupling between Inventory and Tools database tables.
- **Negative / Trade-offs**:
  - Requires maintaining a dedicated set of tables, permissions, and controllers.
  - Cross-module operations (like linking a tool to a Work Order) require contract calls rather than direct SQL joins.
