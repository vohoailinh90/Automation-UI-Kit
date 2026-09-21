import { Check, TriangleAlert } from "lucide-react"
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

/** Các trường của form — chỉ ghi xuống storage khi bấm "Lưu thay đổi". */
type Profile = Pick<Settings, "fullname" | "email" | "location" | "language">

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

function toProfile({ fullname, email, location, language }: Settings): Profile {
  return { fullname, email, location, language }
}

/** Trả về `false` khi trình duyệt chặn storage hoặc hết quota, để UI báo đúng. */
function persist(next: Settings) {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(next))
    return true
  } catch {
    return false
  }
}

const STORAGE_BLOCKED = "Không lưu được — trình duyệt đang chặn bộ nhớ cục bộ"

export function SettingsPage() {
  // `saved` là bản đã nằm trong storage; `draft` là những gì đang gõ trong form.
  // Tách hai thứ này ra để bật một switch không vô tình lưu luôn form chưa submit.
  const [saved, setSaved] = React.useState<Settings>(loadSettings)
  const [draft, setDraft] = React.useState<Profile>(() => toProfile(saved))
  // Ghi hỏng là vấn đề chung của cả trang (storage bị chặn), không riêng control nào,
  // nên chỉ giữ một cờ và để `commit` tự cập nhật sau mỗi lần ghi.
  const [storageBlocked, setStorageBlocked] = React.useState(false)
  const [justSaved, setJustSaved] = React.useState(false)

  // Bản mới nhất giữ trong ref: nếu bấm hai toggle liên tiếp trước khi React
  // kịp re-render, closure `saved` sẽ còn cũ và làm mất thay đổi trước đó.
  const latest = React.useRef(saved)

  function commit(next: Settings) {
    latest.current = next
    setSaved(next)
    const ok = persist(next)
    setStorageBlocked(!ok)
    return ok
  }

  function updateDraft<K extends keyof Profile>(key: K, value: Profile[K]) {
    setDraft((prev) => ({ ...prev, [key]: value }))
    setJustSaved(false)
  }

  // Toggle áp dụng ngay, và chỉ ghi đúng giá trị switch — không kèm draft.
  function toggle(key: "milestoneReminder" | "syncWatchlist", value: boolean) {
    commit({ ...latest.current, [key]: value })
  }

  function handleSubmit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault()
    setJustSaved(commit({ ...latest.current, ...draft }))
  }

  React.useEffect(() => {
    if (!justSaved) return
    const timer = setTimeout(() => setJustSaved(false), 2500)
    return () => clearTimeout(timer)
  }, [justSaved])

  return (
    <div className="flex flex-col gap-6">
      <p aria-live="polite">
        {storageBlocked && (
          <span className="flex items-center gap-2 rounded-lg border border-destructive/40 bg-destructive/10 px-4 py-3 text-sm text-destructive">
            <TriangleAlert className="size-4 shrink-0" />
            {STORAGE_BLOCKED}
          </span>
        )}
      </p>

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
                value={draft.fullname}
                onChange={(e) => updateDraft("fullname", e.target.value)}
              />
            </div>
            <div className="flex flex-col gap-2">
              <Label htmlFor="email">Email</Label>
              <Input
                id="email"
                type="email"
                value={draft.email}
                onChange={(e) => updateDraft("email", e.target.value)}
              />
            </div>
            <div className="flex flex-col gap-2">
              <Label htmlFor="location">Nơi làm việc</Label>
              <Input
                id="location"
                value={draft.location}
                onChange={(e) => updateDraft("location", e.target.value)}
              />
            </div>
            <div className="flex flex-col gap-2">
              <Label htmlFor="language">Ngôn ngữ ưu tiên</Label>
              <Select value={draft.language} onValueChange={(value) => updateDraft("language", value)}>
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
            <p aria-live="polite" className="mr-auto text-sm">
              {justSaved && (
                <span className="flex items-center gap-1.5 text-success">
                  <Check className="size-4" />
                  Đã lưu vào trình duyệt
                </span>
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
              checked={saved.milestoneReminder}
              onCheckedChange={(checked) => toggle("milestoneReminder", checked)}
            />
          </div>
          <Separator />
          <div className="flex items-center justify-between gap-4">
            <div>
              <Label htmlFor="sync-watchlist" className="text-sm font-medium">
                Đồng bộ watchlist với iSPEED
              </Label>
              <p className="text-sm text-muted-foreground">
                {saved.syncWatchlist ? "Đang bật (demo, chưa gọi API thật)" : "Chưa kết nối"}
              </p>
            </div>
            <Switch
              id="sync-watchlist"
              checked={saved.syncWatchlist}
              onCheckedChange={(checked) => toggle("syncWatchlist", checked)}
            />
          </div>
        </CardContent>
      </Card>
    </div>
  )
}
