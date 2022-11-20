import 'package:flutter/material.dart';

import 'package:adaptive_dialog/adaptive_dialog.dart';
import 'package:collection/collection.dart';
import 'package:flutter_gen/gen_l10n/l10n.dart';
import 'package:future_loading_dialog/future_loading_dialog.dart';
import 'package:matrix/matrix.dart';
import 'package:vrouter/vrouter.dart';

import 'package:fluffychat/pages/chat_list/chat_list.dart';
import 'package:fluffychat/pages/chat_list/chat_list_item.dart';
import 'package:fluffychat/pages/chat_list/search_title.dart';
import 'package:fluffychat/widgets/avatar.dart';
import '../../utils/localized_exception_extension.dart';
import '../../widgets/matrix.dart';

class SpaceView extends StatefulWidget {
  final ChatListController controller;
  final ScrollController scrollController;
  const SpaceView(
    this.controller, {
    Key? key,
    required this.scrollController,
  }) : super(key: key);

  @override
  State<SpaceView> createState() => _SpaceViewState();
}

class _SpaceViewState extends State<SpaceView> {
  static final Map<String, Future<GetSpaceHierarchyResponse>> _requests = {};

  String? prevBatch;

  void _refresh() {
    setState(() {
      _requests.remove(widget.controller.activeSpaceId);
    });
  }

  Future<GetSpaceHierarchyResponse> getFuture(String activeSpaceId) =>
      _requests[activeSpaceId] ??= Matrix.of(context).client.getSpaceHierarchy(
            activeSpaceId,
            maxDepth: 1,
            from: prevBatch,
          );

  void _onJoinSpaceChild(Room room) async {
    final client = Matrix.of(context).client;
    if (client.getRoomById(room.id) == null) {
      final space = client.getRoomById(widget.controller.activeSpaceId!);
      final result = await showFutureLoadingDialog(
        context: context,
        future: () async {
          await client.joinRoom(room.id,
              serverName: space?.spaceChildren
                  .firstWhereOrNull((child) => child.roomId == room.id)
                  ?.via);
          if (client.getRoomById(room.id) == null) {
            // Wait for room actually appears in sync
            await client.waitForRoomInSync(room.id, join: true);
          }
        },
      );
      if (result.error != null) return;
      _refresh();
    }
    if (room.isSpace) {
      if (room.id == widget.controller.activeSpaceId) {
        VRouter.of(context).toSegments(['spaces', room.id]);
      } else {
        widget.controller.setActiveSpace(room.id);
      }
      return;
    }
    VRouter.of(context).toSegments(['rooms', room.id]);
  }

  void _onSpaceChildContextMenu(
      [SpaceRoomsChunk? spaceChild, Room? room]) async {
    final client = Matrix.of(context).client;
    final activeSpaceId = widget.controller.activeSpaceId;
    final activeSpace =
        activeSpaceId == null ? null : client.getRoomById(activeSpaceId);
    final action = await showModalActionSheet<SpaceChildContextAction>(
      context: context,
      title: spaceChild?.name ?? room?.displayname,
      message: spaceChild?.topic ?? room?.topic,
      actions: [
        if (room == null)
          SheetAction(
            key: SpaceChildContextAction.join,
            label: L10n.of(context)!.joinRoom,
            icon: Icons.send_outlined,
          ),
        if (spaceChild != null && (activeSpace?.canSendDefaultStates ?? false))
          SheetAction(
            key: SpaceChildContextAction.removeFromSpace,
            label: L10n.of(context)!.removeFromSpace,
            icon: Icons.delete_sweep_outlined,
          ),
        if (room != null)
          SheetAction(
            key: SpaceChildContextAction.leave,
            label: L10n.of(context)!.leave,
            icon: Icons.delete_outlined,
            isDestructiveAction: true,
          ),
      ],
    );
    if (action == null) return;

    switch (action) {
      case SpaceChildContextAction.join:
        _onJoinSpaceChild(room!);
        break;
      case SpaceChildContextAction.leave:
        await showFutureLoadingDialog(
          context: context,
          future: room!.leave,
        );
        break;
      case SpaceChildContextAction.removeFromSpace:
        await showFutureLoadingDialog(
          context: context,
          future: () => activeSpace!.removeSpaceChild(spaceChild!.roomId),
        );
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final client = Matrix.of(context).client;
    final activeSpaceId = widget.controller.activeSpaceId;
    final allSpaces = client.rooms.where((room) => room.isSpace);
    if (activeSpaceId == null) {
      final rootSpaces = allSpaces
          .where(
            (space) => !allSpaces.any(
              (parentSpace) => parentSpace.spaceChildren
                  .any((child) => child.roomId == space.id),
            ),
          )
          .toList();

      return ListView.builder(
        itemCount: rootSpaces.length,
        controller: widget.scrollController,
        itemBuilder: (context, i) => Material(
            color: Theme.of(context).backgroundColor,
            child: _buildItem(rootSpaces[
                i]) /*ListTile(
            leading: Avatar(
              mxContent: rootSpaces[i].avatar,
              name: rootSpaces[i].displayname,
            ),
            title: Text(
              rootSpaces[i].displayname,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(L10n.of(context)!
                .numChats(rootSpaces[i].spaceChildren.length.toString())),
            onTap: () => widget.controller.setActiveSpace(rootSpaces[i].id),
            onLongPress: () => _onSpaceChildContextMenu(null, rootSpaces[i]),
            trailing: const Icon(Icons.chevron_right_outlined),
          ),*/
            ),
      );
    }
    return FutureBuilder<GetSpaceHierarchyResponse>(
        future: getFuture(activeSpaceId),
        builder: (context, snapshot) {
          final response = snapshot.data;
          final error = snapshot.error;
          if (error != null) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(error.toLocalizedString(context)),
                ),
                IconButton(
                  onPressed: _refresh,
                  icon: const Icon(Icons.refresh_outlined),
                )
              ],
            );
          }
          if (response == null) {
            return const Center(child: CircularProgressIndicator.adaptive());
          }

          final parentSpace = allSpaces.firstWhereOrNull((space) => space
              .spaceChildren
              .any((child) => child.roomId == activeSpaceId));

          final spaceChildren = response.rooms;
          final canLoadMore = response.nextBatch != null;
          return VWidgetGuard(
            onSystemPop: (redirector) async {
              if (parentSpace != null) {
                widget.controller.setActiveSpace(parentSpace.id);
                redirector.stopRedirection();
                return;
              }
            },
            child: ListView.builder(
                itemCount: spaceChildren.length + (canLoadMore ? 1 : 0),
                controller: widget.scrollController,
                itemBuilder: (context, i) {
                  if (canLoadMore) {
                    return ListTile(
                      title: Text(L10n.of(context)!.loadMore),
                      trailing: const Icon(Icons.chevron_right_outlined),
                      onTap: () {
                        prevBatch = response.nextBatch;
                        _refresh();
                      },
                    );
                  }
                  final spaceChild = spaceChildren[i];
                  final room = client.getRoomById(spaceChild.roomId);

                  if (room != null) {
                    if (room.id == activeSpaceId) {
                      return Column(
                        children: [
                          _buildItem(room),
                          ListTile(
                            leading: IconButton(
                              tooltip: parentSpace?.name ?? 'Root',
                              icon: Icon(Icons.arrow_back),
                              onPressed: () {
                                widget.controller
                                    .setActiveSpace(parentSpace?.id);
                              },
                            ),
                            trailing: IconButton(
                              icon: Icon(Icons.refresh),
                              onPressed: () {
                                _refresh();
                              },
                            ),
                          ),
                        ],
                      );
                    }

                    return _buildItem(room);
                  }
                  final isSpace = spaceChild.roomType == 'm.space';
                  final topic = spaceChild.topic?.isEmpty ?? true
                      ? null
                      : spaceChild.topic;
                  return SearchTitle(
                    title:
                        spaceChild.name ?? spaceChild.canonicalAlias ?? 'Space',
                    icon: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10.0),
                      child: Avatar(
                        size: 24,
                        mxContent: spaceChild.avatarUrl,
                        name: spaceChild.name,
                        fontSize: 9,
                      ),
                    ),
                    color: Theme.of(context)
                        .colorScheme
                        .secondaryContainer
                        .withAlpha(128),
                    trailing: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16.0),
                      child: Icon(Icons.edit_outlined),
                    ),
                    //onTap: () => _onJoinSpaceChild(room),
                  );
                }
                /*
                  return ListTile(
                    leading: Avatar(
                      mxContent: spaceChild.avatarUrl,
                      name: spaceChild.name,
                    ),
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(
                            spaceChild.name ??
                                spaceChild.canonicalAlias ??
                                L10n.of(context)!.chat,
                            maxLines: 1,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        if (!isSpace) ...[
                          const Icon(
                            Icons.people_outline,
                            size: 16,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            spaceChild.numJoinedMembers.toString(),
                            style: const TextStyle(fontSize: 14),
                          ),
                        ],
                      ],
                    ),
                    onTap: () => _onJoinSpaceChild(room!),
                    onLongPress: () =>
                        widget.controller.toggleSelection(room!.id),
                    //_onSpaceChildContextMenu(spaceChild, room),
                    subtitle: Text(
                      topic ??
                          (isSpace
                              ? L10n.of(context)!.enterSpace
                              : L10n.of(context)!.enterRoom),
                      maxLines: 1,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.onBackground),
                    ),
                    trailing: isSpace
                        ? const Icon(Icons.chevron_right_outlined)
                        : null,
                  );
                  */
                ),
          );
        });
  }

  Widget _buildItem(Room room) {
    return ChatListItem(
      room,

      selected: widget.controller.selectedRoomIds.contains(room.id),
      onTap: widget.controller.selectMode == SelectMode.select
          ? () => widget.controller.toggleSelection(room.id)
          : null,
      trailing: room.isSpace && room.id != widget.controller.activeSpaceId
          ? IconButton(
              icon: Icon(Icons.chevron_right_outlined),
              onPressed: () {
                _onJoinSpaceChild(room);
              },
            )
          : null,
      onLongPress: () => widget.controller.toggleSelection(room.id),
      //onLongPress: () => _onSpaceChildContextMenu(spaceChild, room),
      activeChat: widget.controller.activeChat == room.id,
    );
  }
}

enum SpaceChildContextAction {
  join,
  leave,
  removeFromSpace,
}
