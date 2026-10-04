# Changelog

## v1.3.0

- After you list or join a Mythic+ group in the Group Finder, the party
  keystone list gives every keystone for the listed dungeon a gold icon border,
  so you can see at a glance whose key the group is running. Addons cannot
  read the listing's key level, so only the dungeon is matched.
- 在预创建队伍中发布或加入大秘境队伍后,队伍钥石列表会为持有该副本钥石的
  成员显示金色图标边框,一眼看出本队要打的是谁的钥石。插件无法读取预组的
  钥石层数,因此只按副本匹配。

## v1.2.0

- The weekly/season panel no longer counts runs from previous seasons, refreshes
  as soon as the server reports a finished key, and lists dungeons from the
  highest key level down. The keystone list's teleport click area is now
  limited to the dungeon icon, so clicks on the text pass through.
- 每周/赛季记录面板不再计入往季的次数,完成大秘境后会随服务器数据及时刷新,
  地下城记录按层数从高到低排序。队伍钥石列表的传送点击区域缩小至副本图标,
  点击文字区域可穿透至列表后方。

## v1.1.0

- Party keystone list rows are now click-to-teleport: clicking a row casts that
  dungeon's teleport, with a tooltip showing the spell and its live cooldown.
  Also fixes the Skyreach teleport showing as unlearned, duplicated teleport
  announcements, and the English client falling back to a Chinese announce
  template; dungeon data updated for Midnight Season 2.
- 队伍钥石列表支持点击传送:点击列表中的任意条目即可施放该副本的传送法术,
  鼠标悬停显示法术名与实时冷却。同时修复通天峰传送显示未学会、传送广播重复
  发送、英文客户端广播模板仍为中文等问题,并更新午夜第二赛季副本数据。

## v1.0.0

- First public release. Ships the score overlay, weekly/season history panel,
  teleport announce, party keystone list and in-dungeon center banner in one
  addon, with a full AceGUI settings panel and localisation for enUS, zhCN
  and zhTW.
- 首个公开版本。将副本得分覆盖、每周/赛季记录面板、传送广播、队伍钥石列表
  与副本内中央钥石横幅整合到同一插件,提供完整的 AceGUI 设置面板与
  英文、简体中文、繁体中文本地化。
