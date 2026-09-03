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

export function SettingsPage() {
  return (
    <div className="flex flex-col gap-6">
      <Card>
        <CardHeader>
          <CardTitle>Thông tin cá nhân</CardTitle>
          <CardDescription>Cập nhật thông tin hiển thị trong app</CardDescription>
        </CardHeader>
        <CardContent className="grid gap-4 sm:grid-cols-2">
          <div className="flex flex-col gap-2">
            <Label htmlFor="fullname">Họ và tên</Label>
            <Input id="fullname" defaultValue="Võ Hoài Linh" />
          </div>
          <div className="flex flex-col gap-2">
            <Label htmlFor="email">Email</Label>
            <Input id="email" type="email" defaultValue="vohoailinh90@gmail.com" />
          </div>
          <div className="flex flex-col gap-2">
            <Label htmlFor="location">Nơi làm việc</Label>
            <Input id="location" defaultValue="Nagano / Saitama, Nhật Bản" />
          </div>
          <div className="flex flex-col gap-2">
            <Label htmlFor="language">Ngôn ngữ ưu tiên</Label>
            <Select defaultValue="vi">
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
        <CardFooter className="justify-end border-t">
          <Button>Lưu thay đổi</Button>
        </CardFooter>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>Kết nối &amp; thông báo</CardTitle>
          <CardDescription>Cấu hình nguồn dữ liệu cho dashboard</CardDescription>
        </CardHeader>
        <CardContent className="flex flex-col gap-4">
          <div className="flex items-center justify-between gap-4">
            <div>
              <p className="text-sm font-medium">Nhắc milestone sắp tới hạn</p>
              <p className="text-sm text-muted-foreground">Gửi thông báo trước 2 ngày</p>
            </div>
            <Button variant="outline" size="sm">
              Bật
            </Button>
          </div>
          <Separator />
          <div className="flex items-center justify-between gap-4">
            <div>
              <p className="text-sm font-medium">Đồng bộ watchlist với iSPEED</p>
              <p className="text-sm text-muted-foreground">Chưa kết nối</p>
            </div>
            <Button variant="outline" size="sm">
              Kết nối
            </Button>
          </div>
        </CardContent>
      </Card>
    </div>
  )
}
