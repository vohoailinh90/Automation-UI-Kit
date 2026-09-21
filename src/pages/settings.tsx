import { Check } from "lucide-react"
import * as React from "react"

import { Button } from "@/components/ui/button"
import { Card, CardContent, CardDescription, CardFooter, CardHeader, CardTitle } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select"
import { Separator } from "@/components/ui/separator"
import { Switch } from "@/components/ui/switch"

type Settings = {
  fullname: string
  email: string
  location: string
  language: string
  milestoneReminder: boolean
  syncWatchlist: boolean
}

const STORAGE_KEY = "automation-ui-kit-settings"

const defaultSettings: Settings = {
  fullname: "Võ Hoài Linh",
  email: "vohoailinh90@gmail.com",
  location: "Nagano / Saitama, Nhật Bản",
  language: "vi",
  milestoneReminder: true,
  syncWatchlist: false,
}

function loadSettings(): Settings {
  try {
    const stored = localStorage.getItem(STORAGE_KEY)
    if (!stored) return defaultSettings
    return { ...defaultSettings, ...(JSON.parse(stored) as Partial<Settings>) }
  } catch {
    // localStorage bị chặn hoặc JSON hỏng — quay về giá trị mặc định.
    return defaultSettings
  }
}

export function SettingsPage() {
  const [settings, setSettings] = React.useState<Settings>(loadSettings)
  const [saved, setSaved] = React.useState(false)

  function update<K extends keyof Settings>(key: K, value: Settings[K]) {
    setSettings((prev) => ({ ...prev, [key]: value }))
    setSaved(false)
  }

  // Toggle được áp dụng ngay, không chờ nút "Lưu thay đổi".
  function updateAndPersist<K extends keyof Settings>(key: K, value: Settings[K]) {
    const next = { ...settings, [key]: value }
    setSettings(next)
    persist(next)
  }

  function persist(next: Settings) {
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(next))
    } catch {
      // Không chặn UI nếu trình duyệt không cho ghi localStorage.
    }
  }

  function handleSubmit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault()
    persist(settings)
    setSaved(true)
  }

  React.useEffect(() => {
    if (!saved) return
    const timer = setTimeout(() => setSaved(false), 2500)
    return () => clearTimeout(timer)
  }, [saved])

  return (
    <div className="flex flex-col gap-6">
      <form onSubmit={handleSubmit}>
        <Card>
          <CardHeader>
            <CardTitle>Thông tin cá nhân</CardTitle>
            <CardDescription>Cập nhật thông tin hiển thị trong app</CardDescription>
          </CardHeader>
          <CardContent className="grid gap-4 sm:grid-cols-2">
            <div className="flex flex-col gap-2">
              <Label htmlFor="fullname">Họ và tên</Label>
              <Input
                id="fullname"
                value={settings.fullname}
                onChange={(e) => update("fullname", e.target.value)}
              />
            </div>
            <div className="flex flex-col gap-2">
              <Label htmlFor="email">Email</Label>
              <Input
                id="email"
                type="email"
                value={settings.email}
                onChange={(e) => update("email", e.target.value)}
              />
            </div>
            <div className="flex flex-col gap-2">
              <Label htmlFor="location">Nơi làm việc</Label>
              <Input
                id="location"
                value={settings.location}
                onChange={(e) => update("location", e.target.value)}
              />
            </div>
            <div className="flex flex-col gap-2">
              <Label htmlFor="language">Ngôn ngữ ưu tiên</Label>
              <Select value={settings.language} onValueChange={(value) => update("language", value)}>
                <SelectTrigger id="language" className="w-full">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="vi">Tiếng Việt</SelectItem>
                  <SelectItem value="ja">日本語</SelectItem>
                  <SelectItem value="en">English</SelectItem>
                </SelectContent>
              </Select>
            </div>
          </CardContent>
          <CardFooter className="items-center justify-end gap-3 border-t">
            <p aria-live="polite" className="mr-auto flex items-center gap-1.5 text-sm text-success">
              {saved && (
                <>
                  <Check className="size-4" />
                  Đã lưu vào trình duyệt
                </>
              )}
            </p>
            <Button type="submit">Lưu thay đổi</Button>
          </CardFooter>
        </Card>
      </form>

      <Card>
        <CardHeader>
          <CardTitle>Kết nối &amp; thông báo</CardTitle>
          <CardDescription>Cấu hình nguồn dữ liệu cho dashboard</CardDescription>
        </CardHeader>
        <CardContent className="flex flex-col gap-4">
          <div className="flex items-center justify-between gap-4">
            <div>
              <Label htmlFor="milestone-reminder" className="text-sm font-medium">
                Nhắc milestone sắp tới hạn
              </Label>
              <p className="text-sm text-muted-foreground">Gửi thông báo trước 2 ngày</p>
            </div>
            <Switch
              id="milestone-reminder"
              checked={settings.milestoneReminder}
              onCheckedChange={(checked) => updateAndPersist("milestoneReminder", checked)}
            />
          </div>
          <Separator />
          <div className="flex items-center justify-between gap-4">
            <div>
              <Label htmlFor="sync-watchlist" className="text-sm font-medium">
                Đồng bộ watchlist với iSPEED
              </Label>
              <p className="text-sm text-muted-foreground">
                {settings.syncWatchlist ? "Đang bật (demo, chưa gọi API thật)" : "Chưa kết nối"}
              </p>
            </div>
            <Switch
              id="sync-watchlist"
              checked={settings.syncWatchlist}
              onCheckedChange={(checked) => updateAndPersist("syncWatchlist", checked)}
            />
          </div>
        </CardContent>
      </Card>
    </div>
  )
}
