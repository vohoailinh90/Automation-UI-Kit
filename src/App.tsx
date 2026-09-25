import * as React from "react"
import { BrowserRouter, Route, Routes } from "react-router-dom"

import { AppLayout } from "@/components/layout/app-layout"
import { TasksProvider } from "@/components/tasks-provider"
import { DashboardPage } from "@/pages/dashboard"
import { SettingsPage } from "@/pages/settings"
import { TasksPage } from "@/pages/tasks"
import { WatchlistPage } from "@/pages/watchlist"

/**
 * Các dashboard mẫu tải trễ: là template để xem rồi copy đi, không phải trang
 * ai cũng mở, nên không bắt người chỉ vào Dashboard phải tải cả ba. `Suspense`
 * nằm quanh `<Outlet>` trong `AppLayout`.
 */
const AutomationPage = React.lazy(() =>
  import("@/pages/automation").then((m) => ({ default: m.AutomationPage })),
)
const OrdersPage = React.lazy(() => import("@/pages/orders").then((m) => ({ default: m.OrdersPage })))
const PortfolioPage = React.lazy(() =>
  import("@/pages/portfolio").then((m) => ({ default: m.PortfolioPage })),
)

function App() {
  return (
    <BrowserRouter>
      <TasksProvider>
        <Routes>
          <Route element={<AppLayout />}>
            <Route index element={<DashboardPage />} />
            <Route path="tasks" element={<TasksPage />} />
            <Route path="watchlist" element={<WatchlistPage />} />
            <Route path="automation" element={<AutomationPage />} />
            <Route path="orders" element={<OrdersPage />} />
            <Route path="portfolio" element={<PortfolioPage />} />
            <Route path="settings" element={<SettingsPage />} />
          </Route>
        </Routes>
      </TasksProvider>
    </BrowserRouter>
  )
}

export default App
