import { BrowserRouter, Route, Routes } from "react-router-dom"

import { AppLayout } from "@/components/layout/app-layout"
import { DashboardPage } from "@/pages/dashboard"
import { SettingsPage } from "@/pages/settings"
import { TasksPage } from "@/pages/tasks"
import { WatchlistPage } from "@/pages/watchlist"

function App() {
  return (
    <BrowserRouter>
      <Routes>
        <Route element={<AppLayout />}>
          <Route index element={<DashboardPage />} />
          <Route path="tasks" element={<TasksPage />} />
          <Route path="watchlist" element={<WatchlistPage />} />
          <Route path="settings" element={<SettingsPage />} />
        </Route>
      </Routes>
    </BrowserRouter>
  )
}

export default App
