-- Live lists (Objective 1): the tables the app watches. Firestore
-- snapshot listeners become Supabase Realtime changes, which honour each
-- subscriber's row level security, so a listener sees what a query would.
--
-- The audit log is read on request, never watched, and stays out.

alter publication supabase_realtime add table
  public.users,
  public.facilities,
  public.assets,
  public.damage_reports,
  public.report_status_history,
  public.work_orders,
  public.work_order_materials_used,
  public.work_order_materials_allocated,
  public.tasks,
  public.accomplishment_reports,
  public.inventory_items,
  public.inventory_transactions,
  public.material_requests,
  public.tools,
  public.tool_loans,
  public.feedback,
  public.notifications,
  public.app_config;
