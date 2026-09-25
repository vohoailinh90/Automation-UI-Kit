/**
 * Dữ liệu mẫu cho dashboard Orders: đơn thử nghiệm mẫu (sample test orders).
 *
 * Luồng mô phỏng theo quy trình của Test-order-tracker (bước 15–18):
 *
 *     tạo đơn → 15 gửi yêu cầu → 16 nhận mẫu (Role B)  → 18 giao kết quả → đóng
 *               (Người yêu cầu)   17 giờ công (Role A)     (Role B)          (Người yêu cầu)
 *
 * Bước 16 và 17 treo trên cùng một mail yêu cầu nên mở **song song**.
 *
 * **Dữ liệu mẫu, tất định** (xem `src/lib/mock.ts`). Trạng thái không được lưu
 * mà **dẫn xuất từ các mốc ngày** — như `Order.status` ở Test-order-tracker —
 * nên hỏi "tuần trước có bao nhiêu đơn trễ" chỉ là tính lại ở một ngày khác
 * (`statusOn(order, -7)`), không phải lưu thêm bảng lịch sử nào.
 */

import { formatShortDate, mockDay, randomFor } from "@/lib/mock"

export type OrderStatus = "draft" | "requested" | "in-progress" | "delivered" | "closed"

export const orderStatuses: OrderStatus[] = ["draft", "requested", "in-progress", "delivered", "closed"]

export const orderStatusLabel: Record<OrderStatus, string> = {
  draft: "Nháp",
  requested: "Đã gửi yêu cầu",
  "in-progress": "Đang thử nghiệm",
  delivered: "Đã giao kết quả",
  closed: "Đã đóng",
}

/** Ai đang giữ một bước đang mở. */
export type Holder = "requester" | "role-a" | "role-b"

export const holderLabel: Record<Holder, string> = {
  requester: "Người yêu cầu",
  "role-a": "Role A · giờ công",
  "role-b": "Role B · mẫu & giao kết quả",
}

/**
 * Mốc ngày tính từ `MOCK_TODAY`: 0 = hôm nay, âm = đã qua, dương = tương lai.
 * Mốc ở tương lai nghĩa là bước đó **chưa xảy ra** tính tới hôm nay.
 */
type DayOffset = number

export type TestOrder = {
  number: string
  customer: string
  project: string
  productGroup: string
  created: DayOffset
  /** Hạn giao kết quả đã hứa (est. delivery). */
  due: DayOffset
  request: DayOffset
  samples: DayOffset
  hours: DayOffset
  delivered: DayOffset
  closed: DayOffset
}

const groups = [
  { name: "Van", project: "Valve Line A", lead: 12 },
  { name: "Khuôn ép", project: "Injection Mold X2", lead: 20 },
  { name: "Phụ kiện ống", project: "Fitting Series 9", lead: 9 },
] as const

const customers = ["Khách hàng A", "Khách hàng B", "Khách hàng C", "Khách hàng D", "Khách hàng E"]
// Trọng số khách hàng: vài khách lớn chiếm phần lớn đơn, như thực tế.
const customerWeights = [0.34, 0.26, 0.18, 0.13, 0.09]

/** Số ngày lịch sử đơn. */
export const ORDER_HISTORY_DAYS = 112

function isWeekend(offset: DayOffset) {
  const weekday = new Date(mockDay(-offset) * 1000).getUTCDay()
  return weekday === 0 || weekday === 6
}

function pickWeighted(r: number) {
  let acc = 0
  for (let i = 0; i < customerWeights.length; i += 1) {
    acc += customerWeights[i]
    if (r < acc) return customers[i]
  }
  return customers[customers.length - 1]
}

function generate(): TestOrder[] {
  const rand = randomFor("orders")
  const out: TestOrder[] = []
  for (let created = -(ORDER_HISTORY_DAYS - 1); created <= 0; created += 1) {
    if (isWeekend(created)) continue
    const count = 1 + Math.floor(rand() * 3)
    for (let n = 0; n < count; n += 1) {
      const group = groups[Math.floor(rand() * groups.length)]
      const customer = pickWeighted(rand())
      // Phần lớn gửi yêu cầu ngay trong ngày hoặc hôm sau; một số nằm nháp lâu hơn.
      const wait = rand()
      const request = created + (wait < 0.55 ? 0 : wait < 0.8 ? 1 : 2 + Math.floor(rand() * 3))
      const samples = request + 1 + Math.floor(rand() * 4)
      const hours = request + 1 + Math.floor(rand() * 6)
      // Thời gian thử nghiệm thật dao động quanh mức đã hứa: đa số kịp, vài đơn
      // trễ — đủ để tỉ lệ đúng hạn không phải 100% cho có.
      const actual = Math.round(group.lead * (0.7 + rand() * 0.45))
      const delivered = Math.max(samples, hours) + Math.max(1, actual - 3)
      const closed = delivered + 1 + Math.floor(rand() * 5)
      // Hạn hứa với khách = thời gian thử nghiệm + vài ngày đệm cho khâu nhận mẫu.
      const due = created + group.lead + 4
      out.push({
        number: "",
        customer,
        project: group.project,
        productGroup: group.name,
        created,
        due,
        request,
        samples,
        hours,
        delivered,
        closed,
      })
    }
  }
  // Kịch bản cố ý, như sự cố ở trang Automation: hai đơn có hạn vừa qua bị kẹt
  // mẫu từ nhà cung cấp — mẫu về sau hôm nay, nên đơn vẫn mở và đã trễ hạn.
  // Không có ca này thì bảng "Sắp tới hạn" không bao giờ phải hiện dòng trễ.
  for (const order of out.filter((o) => o.due >= -6 && o.due <= -2).slice(0, 2)) {
    order.samples = 1
    order.delivered = 6
    order.closed = 9
  }
  // Số đơn đánh theo thứ tự tạo trong từng tháng: TO-2609-001, TO-2609-002...
  const perMonth = new Map<string, number>()
  for (const order of out) {
    const d = new Date(mockDay(-order.created) * 1000)
    const key = `${String(d.getUTCFullYear()).slice(2)}${String(d.getUTCMonth() + 1).padStart(2, "0")}`
    const seq = (perMonth.get(key) ?? 0) + 1
    perMonth.set(key, seq)
    order.number = `TO-${key}-${String(seq).padStart(3, "0")}`
  }
  return out
}

export const orders: TestOrder[] = generate()

/** Trạng thái của đơn **tính tới ngày `on`** (mặc định hôm nay). */
export function statusOn(order: TestOrder, on: DayOffset = 0): OrderStatus | null {
  if (order.created > on) return null
  if (order.closed <= on) return "closed"
  if (order.delivered <= on) return "delivered"
  if (order.samples <= on || order.hours <= on) return "in-progress"
  if (order.request <= on) return "requested"
  return "draft"
}

/** Đơn còn mở = chưa giao kết quả. Đã giao mà chưa đóng thì hết trễ hạn. */
export function isOpen(order: TestOrder, on: DayOffset = 0) {
  const status = statusOn(order, on)
  return status === "draft" || status === "requested" || status === "in-progress"
}

export function isLate(order: TestOrder, on: DayOffset = 0) {
  return isOpen(order, on) && order.due < on
}

/** Các bước đang mở và ai giữ chúng — bước 16 và 17 có thể cùng mở. */
export function openHolders(order: TestOrder, on: DayOffset = 0): Holder[] {
  const status = statusOn(order, on)
  if (status === "draft") return ["requester"]
  if (status === "requested" || status === "in-progress") {
    const holders: Holder[] = []
    if (order.samples > on) holders.push("role-b")
    if (order.hours > on) holders.push("role-a")
    // Cả mẫu lẫn giờ công đã xong: chỉ còn chờ Role B giao kết quả.
    return holders.length > 0 ? holders : ["role-b"]
  }
  if (status === "delivered") return ["requester"]
  return []
}

/** Số bước đã xong trong 15–18 (0–4), cho thanh tiến độ. */
export function stepsDone(order: TestOrder, on: DayOffset = 0) {
  return [order.request, order.samples, order.hours, order.delivered].filter((d) => d <= on).length
}

/** Ảnh chụp các chỉ số tại ngày `on`. */
export function snapshot(on: DayOffset = 0) {
  const known = orders.filter((o) => o.created <= on)
  const open = known.filter((o) => isOpen(o, on))
  const late = open.filter((o) => o.due < on)
  const dueSoon = open.filter((o) => o.due >= on && o.due <= on + 7)
  // Đúng hạn: đơn **đã giao** trong 30 ngày tính tới `on`, giao không muộn hơn hạn.
  const delivered30 = known.filter((o) => o.delivered <= on && o.delivered > on - 30)
  const onTime30 = delivered30.filter((o) => o.delivered <= o.due)
  return {
    open: open.length,
    late: late.length,
    dueSoon: dueSoon.length,
    delivered30: delivered30.length,
    onTimeRate: delivered30.length > 0 ? onTime30.length / delivered30.length : 0,
  }
}

/** Số đơn mới và số đơn giao kết quả trong từng tuần (7 ngày), cũ → mới. */
export function weeklyThroughput(weeks = 12) {
  return Array.from({ length: weeks }, (_, i) => {
    const end = -7 * (weeks - 1 - i)
    const start = end - 6
    return {
      label: formatShortDate(mockDay(-start)),
      created: orders.filter((o) => o.created >= start && o.created <= end).length,
      delivered: orders.filter((o) => o.delivered >= start && o.delivered <= end).length,
    }
  })
}

/** Phân bố trạng thái (tính tới hôm nay) của các đơn tạo trong `days` ngày gần nhất. */
export function statusBreakdown(days = 30) {
  const recent = orders.filter((o) => o.created > -days)
  return orderStatuses.map((status) => ({
    status,
    count: recent.filter((o) => statusOn(o) === status).length,
  }))
}

/** Đếm bước đang mở theo người giữ — ai đang là nút thắt. */
export function holderLoad() {
  const counts: Record<Holder, number> = { requester: 0, "role-a": 0, "role-b": 0 }
  for (const order of orders) for (const holder of openHolders(order)) counts[holder] += 1
  return counts
}

/** Số đơn theo khách hàng trong `days` ngày gần nhất, nhiều → ít. */
export function customerMix(days = 90) {
  const recent = orders.filter((o) => o.created > -days)
  return customers
    .map((customer) => ({ customer, count: recent.filter((o) => o.customer === customer).length }))
    .sort((a, b) => b.count - a.count)
}

/**
 * Thời gian từ lúc gửi yêu cầu tới lúc giao kết quả (trung vị, ngày) theo nhóm
 * sản phẩm, trên các đơn đã giao trong `days` ngày gần nhất.
 */
export function leadTimeByGroup(days = 90) {
  return groups.map((group) => {
    const spans = orders
      .filter((o) => o.productGroup === group.name && o.delivered <= 0 && o.delivered > -days)
      .map((o) => o.delivered - o.request)
      .sort((a, b) => a - b)
    const mid = Math.floor(spans.length / 2)
    const median = spans.length === 0 ? 0 : spans.length % 2 ? spans[mid] : (spans[mid - 1] + spans[mid]) / 2
    return { group: group.name, planned: group.lead, median, count: spans.length }
  })
}

/** Đơn còn mở, sắp theo hạn (trễ nhất lên đầu). */
export function upcomingOrders(count: number) {
  return orders
    .filter((o) => isOpen(o))
    .sort((a, b) => a.due - b.due || a.number.localeCompare(b.number))
    .slice(0, count)
}

export function dueDateLabel(order: TestOrder) {
  return formatShortDate(mockDay(-order.due))
}
