#!/usr/bin/env python3
"""Materialize the reviewed two-level overrides; safe to run repeatedly."""
import json
from copy import deepcopy
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
def read(name):
    items = json.loads((ROOT / 'data' / (name + '.json')).read_text())
    for item in items: item.pop('upgrades', None)
    return items
cards, summons, artifacts = read('cards'), read('summons'), read('artifacts')
by_name = {x['name']: x for x in cards}
summon_by_card = {x['card_id']: x for x in summons}
def d(n, e, **kw): return dict(type='damage', amount=n, element=e, **kw)
def s(n, status, target='self'): return dict(type='status', target=target, status=status, stacks=n)
def g(n, e): return dict(type='gain_energy', target='self', element=e, amount=n)
def h(n): return dict(type='heal', target='self', amount=n)
def draw(n): return dict(type='draw', target='self', amount=n)
def think(n): return dict(type='contemplate', target='self', amount=n)
def lose(n, e): return dict(type='lose_energy', target='opponent', element=e, amount=n)
def remove(status): return dict(type='remove_status', target='self', status=status)
def generated(e=''): return dict(type='generate_card', target='self', amount=1, element=e)
def rand(): return dict(type='gain_random_energy', target='self', amount=1)
def discard(target): return dict(type='discard', target=target, amount=1)
seen = set()
def card(name, costs, effects):
    entry = by_name[name]; seen.add(name); entry['cost'] = costs[0]
    entry['upgrades'] = [dict(cost=costs[i+1], effects=effects[i]) for i in range(2)]
def summon(name, costs, health, starts=None, ends=None, spawns=None):
    entry = by_name[name]; seen.add(name); entry['cost'] = costs[0]
    template = summon_by_card[entry['id']]
    template['upgrades'] = []
    entry['upgrades'] = []
    for i in range(2):
        template['upgrades'].append(dict(hp=health[i], turn_start=(starts or [[], []])[i],
            turn_end=(ends or [[], []])[i], on_spawn=(spawns or [[], []])[i]))
        entry['upgrades'].append(dict(cost=costs[i+1], effects=[dict(type='summon', target='self', summon=template['id']+'__'+str(i+1))]))

card('炼金',[0,0,0],[[g(1,'metal'),generated()],[g(2,'metal'),generated()]])
card('伐木诀',[1,1,0],[[lose(3,'wood')],[lose(3,'wood'),s(1,'weak_defense','opponent')]])
card('锋芒',[1,1,1],[[d(14,'metal')],[d(18,'metal')]])
card('砺锋',[1,1,1],[[s(4,'strong_attack')],[s(5,'strong_attack')]])
card('玄铁护身',[1,1,1],[[s(16,'shield'),s(1,'strong_defense')],[s(20,'shield'),s(2,'strong_defense')]])
card('金虹剑诀',[2,2,2],[[d(26,'metal')],[d(32,'metal')]])
card('连锋诀',[2,2,2],[[d(13,'metal'),d(13,'metal')],[d(15,'metal'),d(15,'metal'),d(5,'metal')]])
card('破障雷',[3,3,3],[[dict(type='break_shield',target='opponent',amount=16),d(30,'metal')],[dict(type='break_shield',target='opponent',amount=25),d(35,'metal')]])
summon('玄金铃',[2,2,2],[15,18],starts=[[s(2,'charge')],[s(3,'charge')]],spawns=[[s(1,'charge')],[s(2,'charge')]])
summon('金翎隼',[2,2,2],[14,16],starts=[[d(6,'metal',target='lowest_opponent')],[d(8,'metal',target='lowest_opponent')]])
summon('金灵炉',[2,2,1],[18,18],starts=[[g(1,'water')],[g(1,'water')]],spawns=[[g(1,'water')],[g(1,'water')]])
condition=dict(type='energy_at_least',element='metal',amount=3)
summon('霆光貂',[2,2,2],[12,14],starts=[[d(4,'metal',target='opponent')],[d(5,'metal',target='opponent')]],spawns=[[d(10,'metal',target='opponent',condition=condition)],[d(12,'metal',target='opponent',condition=condition)]])

card('寒针',[1,1,1],[[d(9,'water'),s(3,'weak_attack','opponent')],[d(11,'water'),s(4,'weak_attack','opponent')]])
card('熄焰',[1,1,0],[[lose(3,'fire'),g(1,'water')],[lose(3,'fire'),g(1,'water')]])
card('寒雾',[1,1,0],[[s(3,'vulnerable','opponent')],[s(3,'vulnerable','opponent')]])
card('水刃',[1,1,1],[[d(13,'water')],[d(16,'water'),s(1,'charge')]])
four=[g(1,e) for e in ['metal','wood','fire','earth']]
card('四象归流',[2,1,1],[four,four+[draw(1)]])
card('回澜诀',[2,2,2],[[d(19,'water'),h(7)],[d(24,'water'),h(10)]])
card('潮思',[2,2,2],[[draw(1),think(3)],[draw(2),think(3)]])
card('沧澜引',[3,3,3],[[d(30,'water'),draw(1)],[d(32,'water'),think(3)]])
summon('听雨螺',[2,2,1],[13,14],starts=[[draw(1)],[draw(1)]])
summon('玄水泉',[2,2,1],[19,23],starts=[[g(1,'wood'),h(2)],[g(1,'wood'),h(4)]])
summon('寒汐蛾',[3,3,3],[19,23],ends=[[s(2,'weak','opponent'),s(1,'weak_attack','opponent')],[s(2,'weak','opponent'),s(2,'weak_attack','opponent')]])
summon('灵汐鲤',[3,3,3],[25,30],starts=[[h(4),d(4,'water',target='opponent')],[h(5),d(5,'water',target='opponent')]])

card('同瘴咒',[0,0,0],[[s(6,'poison'),s(6,'poison','opponent')],[s(8,'poison'),s(8,'poison','opponent')]])
card('萌发',[0,0,0],[[g(1,'wood'),h(3)],[g(2,'wood'),h(5)]])
card('瘴毒咒',[1,1,1],[[s(7,'poison','opponent')],[s(9,'poison','opponent')]])
card('回春',[1,1,1],[[s(7,'regen')],[s(9,'regen')]])
card('藤刺',[1,1,1],[[d(13,'wood'),s(1,'bleed','opponent')],[d(16,'wood'),s(2,'bleed','opponent')]])
card('生息',[2,2,2],[[h(24)],[h(30)]])
card('青藤引灵',[2,2,2],[[d(18,'wood'),rand()],[d(20,'wood'),rand(),rand()]])
card('木生火',[2,2,1],[[g(4,'fire')],[g(4,'fire')]])
summon('碧瘴蛙',[1,1,0],[8,8],ends=[[s(3,'poison','opponent')],[s(3,'poison','opponent')]])
summon('春藤鹿',[2,1,1],[13,18],ends=[[h(4)],[h(6)]])
summon('青藤苗',[2,2,1],[18,21],starts=[[g(1,'fire')],[g(1,'fire')]],spawns=[[draw(1)],[draw(1)]])
summon('青棘花灵',[3,3,3],[19,24],starts=[[d(5,'wood',target='opponent'),dict(type='heal_summon',target='summon_self',amount=5)],[d(6,'wood',target='opponent'),dict(type='heal_summon',target='summon_self',amount=6)]])

card('聚火',[0,0,0],[[g(1,'fire'),s(2,'charge')],[g(2,'fire'),s(2,'charge')]])
card('余烬印',[1,1,0],[[s(3,'burn','opponent')],[s(3,'burn','opponent')]])
card('焚妄诀',[1,1,0],[[remove('weak'),s(3,'charge')],[remove('weak'),remove('weak_attack'),s(3,'charge')]])
card('炎咒',[1,1,1],[[d(13,'fire'),d(2,'fire',target='random_opponent')],[d(16,'fire'),d(4,'fire',target='random_opponent')]])
by_name['三昧火']['effects']=[d(15,'fire',scope='all_enemy_summons')]
card('三昧火',[3,3,3],[[d(20,'fire',scope='all_enemy_summons')],[d(25,'fire',scope='all_enemy_summons')]])
card('烙火诀',[2,2,2],[[d(22,'fire'),s(2,'burn','opponent')],[d(26,'fire'),s(3,'burn','opponent')]])
by_name['焚阵']['effects']=[d(12,'fire',scope='all')]
card('焚阵',[1,1,1],[[d(15,'fire',scope='all')],[d(18,'fire',scope='all')]])
fire_condition=dict(type='energy_at_least',element='fire',amount=5)
card('赤阳启明',[3,3,3],[[d(33,'fire'),dict(draw(1),condition=fire_condition)],[d(38,'fire'),dict(think(3),condition=fire_condition)]])
summon('焰尾蜥',[1,1,0],[12,12],ends=[[d(4,'fire',target='lowest_opponent')],[d(5,'fire',target='lowest_opponent')]],spawns=[[d(5,'fire',target='self')],[d(5,'fire',target='self')]])
summon('赤尾狐',[2,2,2],[14,15],ends=[[s(1,'burn','opponent')],[s(2,'burn','opponent')]])
summon('赤焰灯',[2,2,1],[18,21],starts=[[g(1,'earth'),s(1,'charge')],[g(1,'earth'),s(2,'charge')]])
summon('离火鸦',[2,2,2],[14,17],ends=[[d(6,'fire',target='opponent')],[d(8,'fire',target='opponent')]])

card('厚土壁',[1,1,1],[[s(20,'shield')],[s(26,'shield')]])
card('培元壤',[1,1,0],[[dict(type='grow_summon',amount=8),draw(1)],[dict(type='grow_summon',amount=9),draw(1)]])
card('凝岩诀',[1,1,1],[[s(4,'strong_defense')],[s(5,'strong_defense'),s(6,'shield')]])
card('碎岩',[1,1,1],[[d(13,'earth')],[d(16,'earth'),s(2,'strong_attack')]])
card('震手',[2,1,0],[[discard('opponent')],[discard('opponent')]])
card('磐石诀',[2,2,2],[[d(20,'earth'),s(12,'shield')],[d(24,'earth'),s(16,'shield')]])
card('点石成金',[2,2,1],[[g(3,'metal'),generated('metal')],[g(3,'metal'),generated('metal')]])
card('崩山印',[3,3,3],[[d(41,'earth'),discard('self')],[d(47,'earth'),discard('self')]])
summon('岩甲獾',[2,2,2],[20,24],ends=[[s(7,'shield')],[s(9,'shield')]])
summon('坤土碑',[2,2,1],[18,21],starts=[[g(1,'metal')],[g(1,'metal')]],spawns=[[s(8,'shield')],[s(12,'shield')]])
summon('镇山龟',[2,2,2],[20,28],ends=[[s(2,'tenacity')],[s(2,'tenacity')]])
summon('砂背犀',[3,3,3],[28,32],starts=[[d(7,'earth',target='highest_opponent')],[d(9,'earth',target='highest_opponent')]])

artifact_levels={
 '鸣雷尺':[dict(cooldown=3,effects=[d(7,'metal',target='opponent')]),dict(cooldown=2,effects=[d(7,'metal',target='opponent')])],
 '回澜盏':[dict(effects=[dict(type='heal_selected',amount=7)]),dict(effects=[dict(type='heal_selected',amount=10)])],
 '青简卷':[dict(effects=[think(2)]),dict(effects=[think(4)])],
 '赤曜镜':[dict(effects=[g(1,'fire'),s(1,'charge')]),dict(effects=[g(2,'fire'),s(1,'charge')])],
 '镇岳符':[dict(effects=[s(12,'shield')]),dict(effects=[s(16,'shield'),s(1,'tenacity')])],
 '金丝法衣':[dict(durability=5,effects=[s(1,'strong_defense')]),dict(durability=6,effects=[s(2,'strong_defense')])],
 '凝霜纱':[dict(durability=4,resistances=dict(fire=.25)),dict(durability=5,resistances=dict(fire=.30))],
 '春藤衣':[dict(durability=4,effects=[h(3)]),dict(durability=5,effects=[h(4)])],
 '余烬袍':[dict(durability=4,effects=[d(3,'fire',target='opponent')]),dict(durability=5,effects=[d(4,'fire',target='opponent')])],
 '玄岩甲':[dict(durability=4,effects=[s(7,'shield')]),dict(durability=5,effects=[s(9,'shield')])],
 '鸣金佩':[dict(effects=[g(1,'metal'),s(2,'strong_attack')]),dict(effects=[g(2,'metal'),s(2,'strong_attack')])],
 '观澜珠':[dict(effects=[think(3)]),dict(effects=[draw(1),think(3)])],
 '青芽坠':[dict(effects=[h(2)]),dict(effects=[h(4)])],
 '烬心环':[dict(effects=[g(1,'fire'),s(1,'charge')]),dict(effects=[g(2,'fire'),s(1,'charge')])],
 '坤元珏':[dict(effects=[dict(type='grow_summon',target='self',amount=4)]),dict(effects=[dict(type='grow_summon',target='self',amount=6)])],
}
assert seen == set(by_name), set(by_name)-seen
assert len(cards)==60 and len(summons)==20 and len(artifacts)==15
for entry in artifacts:
    if entry['slot']=='implement': entry['cooldown']=3
    if entry['name']=='鸣雷尺':
        entry['target_mode']='none'
        entry['effects']=[d(5,'metal',target='opponent')]
        entry['description']='对手受到5点金伤害。'
    entry['upgrades']=artifact_levels[entry['name']]
for name,items in [('cards',cards),('summons',summons),('artifacts',artifacts)]:
    (ROOT/'data'/(name+'.json')).write_text(json.dumps(items,ensure_ascii=False,indent=2)+'\n')
print('Generated overrides for 60 cards, 20 summons and 15 artifacts.')
