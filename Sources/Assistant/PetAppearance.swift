import Foundation

struct PetAppearance: Identifiable {
    let id: String
    let name: String
    let style: String
    var blinkFrame = 2
    static let all: [PetAppearance] = [
        .init(id: "polyv_female", name: "小保 · 品牌助教", style: "保利威", blinkFrame: 1),
        .init(id: "polyv_male", name: "小威 · 品牌助教", style: "保利威", blinkFrame: 1),
        .init(id: "female", name: "女助教", style: "经典"),
        .init(id: "male", name: "男助教", style: "经典"),
        .init(id: "creator_plush", name: "小绒", style: "毛绒伙伴"),
        .init(id: "creator_engineer", name: "小工", style: "工程师"),
        .init(id: "scholar", name: "国风讲师", style: "教育培训"),
        .init(id: "professor", name: "学术教授", style: "高校科研"),
        .init(id: "astronaut", name: "航天讲解员", style: "航天科普", blinkFrame: 1),
        .init(id: "doctor", name: "健康讲师", style: "医疗健康", blinkFrame: 1),
        .init(id: "finance", name: "金融顾问", style: "金融保险", blinkFrame: 1),
        .init(id: "engineer", name: "制造工程师", style: "工业制造"),
        .init(id: "retail", name: "电商主播", style: "零售电商", blinkFrame: 1),
        .init(id: "chef", name: "餐饮培训师", style: "餐饮服务", blinkFrame: 1),
        .init(id: "lawyer", name: "法律讲师", style: "法律咨询", blinkFrame: 1),
        .init(id: "agriculture", name: "农技专家", style: "农业技术", blinkFrame: 1),
        .init(id: "property", name: "地产顾问", style: "建筑地产", blinkFrame: 1),
        .init(id: "tourism", name: "文旅讲解员", style: "文旅酒店", blinkFrame: 1),
        .init(id: "logistics", name: "物流调度员", style: "物流交通", blinkFrame: 1),
        .init(id: "developer", name: "软件工程师", style: "互联网科技", blinkFrame: 1),
        .init(id: "beauty", name: "美业导师", style: "美业时尚", blinkFrame: 1),
        .init(id: "corporate", name: "政企培训师", style: "政企服务", blinkFrame: 1),
    ]
}

