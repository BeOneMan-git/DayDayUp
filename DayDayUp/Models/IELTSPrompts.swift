import Foundation

// Basic IELTS-style tasks for V0.2. All prompts and model answers are original
// (written for DayDayUp), so they can live in the public repository.
// Topics follow the 12 tags used by the content packs.

struct SpeakingPrompt: Identifiable, Hashable {
    let id: String
    let topic: String
    let question: String
    let zh: String
    let hints: [String]       // shown only when the learner turns hints on
    let outline: [String]     // reference: answer → reason → example
    let model: String         // reference answer, about 45 seconds
}

struct WritingPrompt: Identifiable, Hashable {
    let id: String
    let topic: String
    let task: String
    let zh: String
    let hints: [String]
    let model: String         // reference paragraph, 4–5 sentences
    let phrases: [String]
}

struct CheckDimension: Identifiable, Hashable {
    let id: String
    let title: String
    let en: String
    let questions: [String]
}

enum SelfCheckTemplate {
    static let speaking: [CheckDimension] = [
        CheckDimension(id: "fc", title: "流利与连贯", en: "Fluency & Coherence",
                       questions: ["说满了 45 秒", "中间没有超过 3 秒的长停顿"]),
        CheckDimension(id: "lr", title: "词汇", en: "Lexical Resource",
                       questions: ["用了至少 2 个题目里没有的词", "没有因为找词卡住"]),
        CheckDimension(id: "gra", title: "语法", en: "Grammatical Range & Accuracy",
                       questions: ["用了至少 1 个复合句（because / when / if / which）", "时态和单复数基本没错"]),
        CheckDimension(id: "pr", title: "发音", en: "Pronunciation",
                       questions: ["回听时每个词都听得清", "重音和语调听起来自然"]),
    ]

    static let writing: [CheckDimension] = [
        CheckDimension(id: "tr", title: "任务回应", en: "Task Response",
                       questions: ["回答了题目问的问题", "给了至少 1 个理由或例子"]),
        CheckDimension(id: "cc", title: "连贯与衔接", en: "Coherence & Cohesion",
                       questions: ["句子之间有连接词（first, also, however, so）", "每句都围绕同一个观点"]),
        CheckDimension(id: "lr", title: "词汇", en: "Lexical Resource",
                       questions: ["同一个词没有重复超过 2 次", "用了至少 1 个新学的词"]),
        CheckDimension(id: "gra", title: "语法", en: "Grammatical Range & Accuracy",
                       questions: ["至少有 1 个复合句", "检查过拼写和时态"]),
    ]

    static func empty(_ dims: [CheckDimension]) -> SelfCheck {
        SelfCheck(created: Date(), dims: dims.map { DimCheck(id: $0.id, answers: $0.questions.map { _ in false }, note: "") })
    }
}

enum IELTSBank {
    static let topics = ["科技", "环境", "教育", "健康", "工作", "政府", "经济", "社会", "文化", "媒体", "国际", "交通"]

    static func speaking(_ id: String) -> SpeakingPrompt? { speaking.first { $0.id == id } }
    static func writing(_ id: String) -> WritingPrompt? { writing.first { $0.id == id } }

    static let speaking: [SpeakingPrompt] = [
        SpeakingPrompt(
            id: "sp-tech-1", topic: "科技",
            question: "How often do you use your phone in a day? What do you mostly use it for?",
            zh: "你一天用多少手机？主要用来做什么？",
            hints: ["Say roughly how many hours.", "Name two things you use it for.", "Say whether you want to use it less."],
            outline: ["Answer: about three hours a day.", "Reason: work messages and news.", "Example: reading on the train; wanting less time on short videos."],
            model: "I'd say I use my phone for about three hours a day. Most of that time is for work, because my clients send me messages all day. I also read the news on it while I'm on the train. To be honest, I sometimes waste time on short videos in the evening, so I'm trying to put the phone in another room before I go to bed."),
        SpeakingPrompt(
            id: "sp-tech-2", topic: "科技",
            question: "Do you think robots will do more jobs in the future? Why?",
            zh: "你觉得将来机器人会做更多的工作吗？为什么？",
            hints: ["Give a clear yes or no.", "Name a job robots already do.", "Say which jobs people will still do."],
            outline: ["Answer: yes, especially simple and repeated tasks.", "Reason: machines are cheaper and never get tired.", "Example: factories and warehouses; jobs that need care will stay with people."],
            model: "Yes, I think they will, especially for simple jobs that repeat again and again. For example, many factories and warehouses already use robots to move and pack things, because machines are cheaper in the long run and they never get tired. However, I don't think robots can replace everyone. Jobs that need care and trust, like nurses or teachers, will probably stay with people."),
        SpeakingPrompt(
            id: "sp-env-1", topic: "环境",
            question: "Do you try to save water or electricity at home? How?",
            zh: "你在家会节约用水或用电吗？怎么做？",
            hints: ["Say yes or no first.", "Give two small habits.", "Say why you do it (money or the planet)."],
            outline: ["Answer: yes, in small ways.", "Reason: it saves money and helps the environment.", "Example: turning off lights, shorter showers."],
            model: "Yes, I do, although only in small ways. I always turn off the lights when I leave a room, and I try to keep my showers short, maybe five minutes. Part of the reason is money, because electricity isn't cheap. But I also think if everyone does something small, it really adds up for the environment."),
        SpeakingPrompt(
            id: "sp-env-2", topic: "环境",
            question: "What kind of weather do you like best? Why?",
            zh: "你最喜欢什么样的天气？为什么？",
            hints: ["Name the weather or season.", "Say what you like doing in it.", "Compare it with weather you dislike."],
            outline: ["Answer: cool, sunny autumn days.", "Reason: comfortable for walking; not too hot.", "Example: weekend walks in the park; summer is too humid."],
            model: "I like cool, sunny days best, the kind of weather we usually get in autumn. It's not too hot and not too cold, so it's perfect for going out. On days like that I often take a long walk in the park near my home. In contrast, I really don't like summer here, because it's so hot and humid that I just want to stay inside."),
        SpeakingPrompt(
            id: "sp-edu-1", topic: "教育",
            question: "What subject did you like most at school? Why?",
            zh: "上学时你最喜欢哪一门课？为什么？",
            hints: ["Name the subject.", "Say what made it interesting.", "Say whether it helps you today."],
            outline: ["Answer: mathematics.", "Reason: clear answers; a good teacher.", "Example: it still helps me with work and data today."],
            model: "My favourite subject was mathematics. I liked it because every problem had a clear answer, and it felt great when I finally solved a difficult one. I was also lucky to have a very patient teacher who explained things step by step. Actually, maths still helps me today, because my job involves a lot of numbers and data."),
        SpeakingPrompt(
            id: "sp-edu-2", topic: "教育",
            question: "Do you prefer studying alone or with other people?",
            zh: "你喜欢一个人学习还是和别人一起学习？",
            hints: ["Choose one side.", "Give one reason.", "Say when the other way is useful."],
            outline: ["Answer: mostly alone.", "Reason: I can focus and go at my own speed.", "Example: but for speaking practice, a partner is better."],
            model: "Mostly I prefer studying alone, because I can focus better and go at my own speed. When other people are around, we often start chatting and lose time. That said, for some things a partner is really useful. For example, when I practise speaking English, it's much better to have someone to talk to than to talk to a wall."),
        SpeakingPrompt(
            id: "sp-health-1", topic: "健康",
            question: "What do you usually do to stay healthy?",
            zh: "你平时做什么来保持健康？",
            hints: ["Talk about exercise.", "Talk about food or sleep.", "Say what you want to improve."],
            outline: ["Answer: walking and simple food.", "Reason: easy to keep doing every day.", "Example: 8,000 steps; want to sleep earlier."],
            model: "I try to keep things simple. I walk a lot, usually around eight thousand steps a day, because it's easy to do and I don't need a gym. I also cook at home most evenings, so I know what I'm eating. The thing I really need to improve is sleep, because I often stay up too late reading."),
        SpeakingPrompt(
            id: "sp-health-2", topic: "健康",
            question: "How many hours do you sleep, and is it enough for you?",
            zh: "你睡几个小时？够不够？",
            hints: ["Give a number.", "Say how you feel the next day.", "Say what keeps you awake."],
            outline: ["Answer: about six hours.", "Reason: it's not enough; tired in the afternoon.", "Example: late screen time; plan to stop screens at eleven."],
            model: "On weekdays I sleep about six hours, which honestly isn't enough for me. I can feel it in the afternoon, when it becomes hard to concentrate. The main problem is that I look at screens until late at night. So my plan is to stop using my phone at eleven and read a paper book instead."),
        SpeakingPrompt(
            id: "sp-work-1", topic: "工作",
            question: "What do you do for work or study?",
            zh: "你做什么工作，或者在学什么？",
            hints: ["Name your job or course.", "Describe a normal day.", "Say what you like about it."],
            outline: ["Answer: my job or field.", "Reason: what a normal day looks like.", "Example: the part I enjoy most."],
            model: "I work in finance, and at the moment I also study part-time. A normal day starts with checking the markets, then I spend most of the day analysing data and writing short reports. What I enjoy most is solving problems, when the numbers don't make sense at first and I have to find out why."),
        SpeakingPrompt(
            id: "sp-work-2", topic: "工作",
            question: "Would you prefer to work from home or in an office? Why?",
            zh: "你更愿意在家办公还是去办公室？为什么？",
            hints: ["Choose one.", "Give one advantage.", "Mention one disadvantage."],
            outline: ["Answer: a mix, but mostly home.", "Reason: no commute, quiet for deep work.", "Example: office days are better for meetings."],
            model: "If I had to choose, I'd say mostly from home. I save about an hour a day because I don't have to travel, and it's quieter, so I can concentrate on difficult work. However, I think going to the office once or twice a week is useful, because meetings and quick questions are much easier face to face."),
        SpeakingPrompt(
            id: "sp-gov-1", topic: "政府",
            question: "What public service in your city works well?",
            zh: "你所在的城市，哪一项公共服务做得好？",
            hints: ["Pick one: transport, parks, hospitals, libraries.", "Say why it works well.", "Give a personal example."],
            outline: ["Answer: the metro.", "Reason: fast, cheap and on time.", "Example: I use it every day; better than driving."],
            model: "I think the metro works really well in my city. It's fast, it's cheap, and the trains almost always arrive on time. I use it every day to get to work, and it takes me about thirty minutes, which is much faster than driving in traffic. The only problem is that it's very crowded at rush hour."),
        SpeakingPrompt(
            id: "sp-gov-2", topic: "政府",
            question: "Should the government spend more money on public parks? Why?",
            zh: "政府应该在公园上多花钱吗？为什么？",
            hints: ["Say yes or no.", "Give a reason about health or people.", "Mention what else the money could do."],
            outline: ["Answer: yes, within reason.", "Reason: free place for exercise and relaxing.", "Example: old people and children use parks most."],
            model: "Yes, I think so, as long as the money is used carefully. Parks are free, so everyone can use them to exercise, relax or meet friends, whether they're rich or poor. In my neighbourhood, the park is full of old people in the morning and children in the afternoon. Of course, the government also has other needs, like hospitals, so it's about balance."),
        SpeakingPrompt(
            id: "sp-econ-1", topic: "经济",
            question: "Do you like shopping online or in shops? Why?",
            zh: "你喜欢网购还是去商店买？为什么？",
            hints: ["Choose one.", "Talk about price or time.", "Say what you still buy in shops."],
            outline: ["Answer: mostly online.", "Reason: cheaper and saves time.", "Example: but clothes and shoes in shops, to try them on."],
            model: "Most of the time I shop online, because it's usually cheaper and it saves me a lot of time. I can compare prices in a few minutes and the things arrive the next day. However, I still prefer to buy clothes and shoes in real shops, because I want to try them on first. Returning things online is quite annoying."),
        SpeakingPrompt(
            id: "sp-econ-2", topic: "经济",
            question: "Is it easy for young people to save money today?",
            zh: "现在的年轻人存钱容易吗？",
            hints: ["Give your view.", "Mention housing or prices.", "Suggest one way to save."],
            outline: ["Answer: not really.", "Reason: rent and daily costs are high.", "Example: a simple monthly budget helps."],
            model: "Honestly, I don't think it's easy. Rent in big cities takes a large part of their salary, and everyday things like food and transport keep getting more expensive. On top of that, online shopping makes spending very easy. I think one thing that helps is a simple monthly budget, so you can see where the money actually goes."),
        SpeakingPrompt(
            id: "sp-soc-1", topic: "社会",
            question: "Do you know your neighbours well?",
            zh: "你和邻居熟吗？",
            hints: ["Say yes or no.", "Describe how you meet them.", "Compare with the past."],
            outline: ["Answer: not very well.", "Reason: everyone is busy; apartment life.", "Example: just say hello in the lift; different when I was a child."],
            model: "Not very well, to be honest. I live in a big apartment building, and everyone seems busy, so we usually just say hello in the lift. It was quite different when I was a child. Back then, neighbours often visited each other and shared food. I think we've lost something, although city life makes it hard to keep that kind of community."),
        SpeakingPrompt(
            id: "sp-soc-2", topic: "社会",
            question: "How do people in your country usually celebrate a birthday?",
            zh: "你们国家的人一般怎么过生日？",
            hints: ["Describe a typical birthday.", "Mention food.", "Say how you celebrate."],
            outline: ["Answer: a family meal and a cake.", "Reason: birthdays are about family.", "Example: long noodles for a long life; I keep it simple."],
            model: "Usually people have a meal with their family, and there's often a cake with candles. In China, some families also eat long noodles on a birthday, because they're a symbol of a long life. Young people often go out with friends as well. Personally, I keep it simple, just a nice dinner at home with my family."),
        SpeakingPrompt(
            id: "sp-cult-1", topic: "文化",
            question: "What kind of music do you enjoy?",
            zh: "你喜欢什么样的音乐？",
            hints: ["Name a style or singer.", "Say when you listen to it.", "Say how it makes you feel."],
            outline: ["Answer: quiet music without words.", "Reason: helps me concentrate.", "Example: piano music while working; pop songs when driving."],
            model: "I mostly enjoy quiet music without words, like piano or light jazz. I often listen to it while I'm working, because it helps me concentrate and it doesn't distract me the way songs with lyrics do. When I'm driving, though, I like something more energetic, like old pop songs that I can sing along to."),
        SpeakingPrompt(
            id: "sp-cult-2", topic: "文化",
            question: "Tell me about a traditional festival you like.",
            zh: "说一个你喜欢的传统节日。",
            hints: ["Name the festival.", "Describe what people do.", "Say why you like it."],
            outline: ["Answer: the Mid-Autumn Festival.", "Reason: family time and the full moon.", "Example: mooncakes and a walk under the moon."],
            model: "I really like the Mid-Autumn Festival. It happens in autumn, when the moon is full and very bright. Families get together, have a big dinner and share mooncakes, which are small round cakes with a sweet filling. What I like most is that it feels calm and warm. After dinner, we usually take a walk and look at the moon together."),
        SpeakingPrompt(
            id: "sp-media-1", topic: "媒体",
            question: "How do you usually get the news?",
            zh: "你平时怎么获取新闻？",
            hints: ["Name the app, site or paper.", "Say how often.", "Say why you trust it."],
            outline: ["Answer: news apps and a weekly magazine.", "Reason: quick updates plus deeper analysis.", "Example: headlines in the morning, long articles at the weekend."],
            model: "I get most of my news from apps on my phone, which I check quickly every morning. But headlines don't tell you much, so I also read a weekly magazine for deeper analysis. I usually save the long articles for the weekend, when I have more time. I try to use sources that explain both sides of a story."),
        SpeakingPrompt(
            id: "sp-media-2", topic: "媒体",
            question: "Do you think people spend too much time on social media?",
            zh: "你觉得人们在社交媒体上花的时间太多吗？",
            hints: ["Give your view.", "Give an example you have seen.", "Say what could help."],
            outline: ["Answer: yes, many people do.", "Reason: apps are designed to keep us scrolling.", "Example: people on phones at dinner; time limits can help."],
            model: "Yes, I think a lot of people do, and I include myself sometimes. These apps are designed to keep us scrolling, so it's easy to lose an hour without noticing. I often see friends looking at their phones during dinner, which is a bit sad. I think simple things help, like turning off notifications or setting a daily time limit."),
        SpeakingPrompt(
            id: "sp-intl-1", topic: "国际",
            question: "Which foreign country would you like to visit? Why?",
            zh: "你想去哪个国家旅行？为什么？",
            hints: ["Name the country.", "Give two reasons.", "Say what you would do there."],
            outline: ["Answer: New Zealand.", "Reason: nature and a quiet way of life.", "Example: hiking and seeing the lakes."],
            model: "I'd love to visit New Zealand. I've seen so many pictures of its mountains and lakes, and the nature there looks amazing. I also like the idea of a quieter way of life, away from crowded cities. If I went, I'd spend most of my time hiking. Actually, I'd even like to live there for a while one day."),
        SpeakingPrompt(
            id: "sp-intl-2", topic: "国际",
            question: "Why do you want to learn English?",
            zh: "你为什么想学英语？",
            hints: ["Give your main reason.", "Mention work or study.", "Say what is hardest for you."],
            outline: ["Answer: for work and study.", "Reason: English opens more opportunities.", "Example: reading reports in English; speaking is the hardest part."],
            model: "My main reason is work. In my field, most of the best reports and research are in English, so reading them directly saves me a lot of time. I may also study or work abroad in the future, so I need English for daily life too. For me, the hardest part is speaking, because I often know the words but can't say them fast enough."),
        SpeakingPrompt(
            id: "sp-trans-1", topic: "交通",
            question: "How do you usually travel to work or school?",
            zh: "你平时怎么去上班或上学？",
            hints: ["Name the transport.", "Say how long it takes.", "Say what you do on the way."],
            outline: ["Answer: by metro.", "Reason: fast and avoids traffic.", "Example: forty minutes; I listen to English on the way."],
            model: "I usually take the metro. It takes about forty minutes door to door, which isn't too bad, and I don't have to worry about traffic or parking. I try to use the time well, so I listen to English podcasts or read on my phone. The only thing I don't like is how crowded it gets in the morning."),
        SpeakingPrompt(
            id: "sp-trans-2", topic: "交通",
            question: "What would make traffic in your city better?",
            zh: "怎样才能让你所在城市的交通更好？",
            hints: ["Name the main problem.", "Suggest one solution.", "Say who should do it."],
            outline: ["Answer: fewer cars in the centre.", "Reason: too many cars at rush hour.", "Example: more buses and bike lanes, higher parking prices."],
            model: "I think the main problem is that there are simply too many cars at rush hour. One solution would be to make public transport more attractive, with more buses and better bike lanes. At the same time, the city could make parking in the centre more expensive. If driving is less convenient, more people will choose other ways to travel."),
    ]

    static let writing: [WritingPrompt] = [
        WritingPrompt(
            id: "wr-tech", topic: "科技",
            task: "Some people say smartphones make us less social. Do you agree? Write 3–5 sentences with one reason and one example.",
            zh: "有人说智能手机让我们不那么爱社交。你同意吗？写 3–5 句，给一个理由和一个例子。",
            hints: ["Start with a clear opinion.", "Give one reason.", "Add one example from daily life."],
            model: "I partly agree that smartphones make us less social. They keep us connected with people far away, but they often take our attention away from the people next to us. For example, it is common to see a family at a restaurant where everyone is looking at a screen. In my view, the problem is not the phone itself but how we choose to use it.",
            phrases: ["I partly agree that ...", "For example, it is common to see ...", "In my view, the problem is not ... but ..."]),
        WritingPrompt(
            id: "wr-env", topic: "环境",
            task: "What is one simple thing people can do to protect the environment? Explain why it helps.",
            zh: "普通人可以做哪一件简单的事来保护环境？解释为什么有用。",
            hints: ["Name one action.", "Explain how it helps.", "Say why it is easy to do."],
            model: "One simple thing people can do is to use less plastic. Plastic bags and bottles take hundreds of years to break down, and many of them end up in rivers and the sea. If everyone carries a reusable bag and a water bottle, the amount of waste can fall quickly. It costs almost nothing and only needs a small change in habit.",
            phrases: ["One simple thing people can do is ...", "If everyone ..., ... can fall quickly.", "It only needs a small change in habit."]),
        WritingPrompt(
            id: "wr-edu", topic: "教育",
            task: "Is it better to learn English by reading or by listening? Give your opinion and one reason.",
            zh: "学英语，读更好还是听更好？给出观点和一个理由。",
            hints: ["Choose one, or say both.", "Give a reason.", "Say how you do it yourself."],
            model: "I believe the best way is to combine reading and listening. Reading helps us learn new words and see how sentences are built. Listening, on the other hand, trains our ears for real speed and pronunciation. That is why I like listening to an article while reading the same text at the same time.",
            phrases: ["I believe the best way is to ...", "On the other hand, ...", "That is why I like ..."]),
        WritingPrompt(
            id: "wr-health", topic: "健康",
            task: "Describe one healthy habit you have, and explain why it is useful.",
            zh: "描述你的一个健康习惯，并解释它为什么有用。",
            hints: ["Name the habit.", "Say when you do it.", "Explain the benefit."],
            model: "One healthy habit I have is walking for thirty minutes after dinner. I started doing it last year because I spent most of the day sitting at a desk. Walking helps my body digest food and also clears my mind after a long day. Since I started, I have been sleeping better and feeling less stressed.",
            phrases: ["One healthy habit I have is ...", "I started doing it because ...", "Since I started, I have been ..."]),
        WritingPrompt(
            id: "wr-work", topic: "工作",
            task: "Would you rather have a high salary or more free time? Explain your choice.",
            zh: "你更想要高薪还是更多空闲时间？解释你的选择。",
            hints: ["Choose one.", "Give a personal reason.", "Admit one downside."],
            model: "At this stage of my life, I would choose more free time over a higher salary. Money is important, but after a certain level it does not make people much happier. Free time allows me to study, exercise and be with my family. Of course, this choice is only possible if my basic needs are already covered.",
            phrases: ["At this stage of my life, I would choose ... over ...", "... allows me to ...", "Of course, this is only possible if ..."]),
        WritingPrompt(
            id: "wr-gov", topic: "政府",
            task: "Should public transport be free for everyone? Give one advantage and one disadvantage.",
            zh: "公共交通应该对所有人免费吗？给出一个好处和一个坏处。",
            hints: ["State the advantage.", "State the disadvantage.", "Finish with your view."],
            model: "Making public transport free would have a clear advantage: more people would leave their cars at home, so traffic and pollution would fall. However, the system would still cost a lot of money, and the government would have to raise taxes to pay for it. Overall, I think lower prices for students and old people would be a fairer solution.",
            phrases: ["... would have a clear advantage: ...", "However, ...", "Overall, I think ... would be a fairer solution."]),
        WritingPrompt(
            id: "wr-econ", topic: "经济",
            task: "Why do some people prefer to rent a home instead of buying one? Give two reasons.",
            zh: "为什么有些人宁愿租房也不买房？给出两个理由。",
            hints: ["First reason: money.", "Second reason: freedom.", "Use firstly / secondly."],
            model: "There are two main reasons why some people prefer to rent. Firstly, buying a home in a big city needs a huge amount of money, and many young people cannot afford it. Secondly, renting gives people more freedom, because they can move easily when they change jobs. For these reasons, renting can be a sensible choice, especially early in a career.",
            phrases: ["There are two main reasons why ...", "Firstly, ... Secondly, ...", "For these reasons, ..."]),
        WritingPrompt(
            id: "wr-soc", topic: "社会",
            task: "How has technology changed the way families spend time together?",
            zh: "科技怎样改变了家人一起相处的方式？",
            hints: ["Give one positive change.", "Give one negative change.", "End with a short conclusion."],
            model: "Technology has changed family life in both good and bad ways. On the positive side, video calls let families stay in touch even when they live in different cities. On the negative side, family members at home often sit together but look at their own screens. It seems that technology brings distant people closer but can push close people apart.",
            phrases: ["... has changed ... in both good and bad ways.", "On the positive side, ... On the negative side, ...", "It seems that ..."]),
        WritingPrompt(
            id: "wr-cult", topic: "文化",
            task: "Should museums be free to visit? Give your opinion with one reason.",
            zh: "博物馆应该免费参观吗？给出观点和一个理由。",
            hints: ["Say yes or no.", "Give one reason.", "Mention who benefits."],
            model: "I think museums should be free, at least for their main collections. Museums keep the history and culture of a country, and everyone should be able to learn from them, not only people with money. Free entry also encourages families to visit more often. If museums need extra income, they could charge for special exhibitions instead.",
            phrases: ["I think ... should be free, at least for ...", "... encourages ... to ...", "If ..., they could ... instead."]),
        WritingPrompt(
            id: "wr-media", topic: "媒体",
            task: "Is it a good idea for children to watch the news? Explain your view.",
            zh: "让孩子看新闻是个好主意吗？解释你的看法。",
            hints: ["Give your view.", "Explain one benefit or risk.", "Suggest how parents can help."],
            model: "I think it can be a good idea if parents are careful. Watching the news helps children understand the world and learn about different places and problems. However, some stories are violent or frightening, so young children should not watch them alone. The best approach is for parents to watch with them and explain what is happening.",
            phrases: ["I think it can be a good idea if ...", "However, ...", "The best approach is for ... to ..."]),
        WritingPrompt(
            id: "wr-intl", topic: "国际",
            task: "What is the most useful thing about travelling abroad? Give one example.",
            zh: "出国旅行最有用的是什么？举一个例子。",
            hints: ["Name the benefit.", "Give an example.", "Explain what you learned."],
            model: "In my opinion, the most useful thing about travelling abroad is learning how other people think. When you see a different culture with your own eyes, you realise that your way is not the only way. For example, on a trip to Japan I noticed how quiet people are on trains, which made me more aware of my own behaviour. Experiences like this are hard to get from books.",
            phrases: ["In my opinion, the most useful thing about ... is ...", "When you ..., you realise that ...", "Experiences like this are hard to get from ..."]),
        WritingPrompt(
            id: "wr-trans", topic: "交通",
            task: "Should cities build more roads or more bike lanes? Give your opinion and one reason.",
            zh: "城市应该多修路还是多修自行车道？给出观点和一个理由。",
            hints: ["Choose one.", "Give a reason.", "Mention a result for the city."],
            model: "I believe cities should build more bike lanes rather than more roads. New roads often fill up with cars again within a few years, so traffic does not really improve. Bike lanes, on the other hand, encourage people to cycle, which is cheap, healthy and clean. As a result, the city becomes quieter and the air becomes cleaner.",
            phrases: ["I believe ... rather than ...", "... on the other hand, ...", "As a result, ..."]),
    ]
}
