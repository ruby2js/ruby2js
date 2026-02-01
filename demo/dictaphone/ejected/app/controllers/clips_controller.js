import React from "react";

function renderView(View, props) {
  return View.constructor.name === "AsyncFunction" ? View(props) : React.createElement(
    View,
    props
  )
};

import { Clip } from "../models/clip.js";
import { ClipViews } from "../views/clips.js";
import { ClipTurboStreams } from "../views/clips_turbo_streams.js";
import { clips_path } from "../../config/routes.js";

export const ClipsController = (() => {
  async function index(context) {
    let clips = await Clip.order({created_at: "desc"});
    context.viewProps = {clips};
    return renderView(ClipViews.index, {$context: context, clips})
  };

  async function show(context, id) {
    let clip = await Clip.find(id);
    context.viewProps = {clip};
    return renderView(ClipViews.show, {$context: context, clip})
  };

  async function create(context, params) {
    let clip = new Clip(params);

    if (await clip.save()) {
      return (context?.request?.headers?.accept || "").includes("text/vnd.turbo-stream.html") ? {turbo_stream: ClipTurboStreams.create({
        $context: context,
        clip
      })} : {redirect: clips_path()}
    } else {
      return {redirect: clips_path()}
    }
  };

  async function update(context, id, params) {
    let clip = await Clip.find(id);

    if (await clip.update(params)) {
      return (context?.request?.headers?.accept || "").includes("text/vnd.turbo-stream.html") ? {turbo_stream: ClipTurboStreams.update({
        $context: context,
        clip
      })} : {redirect: clips_path(), notice: "Transcript updated."}
    } else {
      return {redirect: clips_path()}
    }
  };

  async function destroy(context, id) {
    let clip = await Clip.find(id);
    if (clip.audio.attached) clip.audio.purge;
    await clip.destroy();

    return (context?.request?.headers?.accept || "").includes("text/vnd.turbo-stream.html") ? {turbo_stream: ClipTurboStreams.destroy({
      $context: context,
      clip
    })} : {redirect: clips_path(), notice: "Clip deleted."}
  };

  return {index, show, create, update, destroy}
})()