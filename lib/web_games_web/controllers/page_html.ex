defmodule WebGamesWeb.PageHTML do
  use WebGamesWeb, :html

  embed_templates "page_html/*"

  attr :href, :string, required: true
  attr :img_src, :string, required: true
  attr :name, :string, required: true
  attr :enabled, :boolean, default: true
  def game_card(%{enabled: true} = assigns) do
    ~H"""
    <a href={@href} class="block max-w-xs border-white border-4 p-4 m-4 w-[275px] rounded-lg bg-slate-500 hover:bg-slate-400">
      <div class="flex justify-center py-2 h-[275px]"><img class="border-black border-4 rounded-lg" src={@img_src} /></div>
      <div class="font-bold text-4xl text-center w-full"><%= @name %></div>
    </a>
    """
  end

  def game_card(%{enabled: false} = assigns) do
    ~H"""
    <div class="block max-w-xs border-gray border-4 p-4 m-4 w-[275px] rounded-lg bg-gray-500">
      <div class="flex justify-center py-2 h-[275px]"><img class="grayscale border-black border-4 rounded-lg" src={@img_src} /></div>
      <div class="font-bold text-4xl text-center w-full text-gray-800"><%= @name %></div>
    </div>
    """
  end
end
