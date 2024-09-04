defmodule CodeMod do
  def mod_files(file_paths) do
    file_paths |> Enum.each(&mod_file/1)
  end

  def mod_file(input_path, output_path \\ nil) do
    output_path =
      if is_nil(output_path) do
        input_path
      else
        output_path
      end

    input_path
    |> File.read!()
    |> Code.string_to_quoted_with_comments(
      literal_encoder: &{:ok, {:__block__, &2, [&1]}},
      token_metadata: true,
      escape: false,
      unescape: false
    )
    |> then(fn {:ok, ast, comments} ->
      {after_ast, _acc} =
        Macro.postwalk(ast, [], fn
          {:__block__, [], children} = node, acc ->
            idx =
              Enum.find_index(children, fn
                :__delete_me__ -> true
                _ -> false
              end)

            if is_nil(idx) do
              {node, acc}
            else
              {before_children, after_children} = Enum.split(children, idx)

              survivors =
                before_children
                |> Kernel.++(acc)
                |> Kernel.++(after_children)
                |> Enum.reject(&(&1 == :__delete_me__))

              {{:__block__, [], survivors}, []}
            end

          {:alias, _, [{:__aliases__, _, _} | _]} = node, acc ->
            {node, acc}

          {:alias, _, _children} = node, acc ->
            aliases = reformat(node, [])

            {:__delete_me__, acc ++ aliases}

          node, acc ->
            {node, acc}
        end)

      File.write!(
        output_path,
        Code.quoted_to_algebra(after_ast, comments: comments, escape: false)
        |> Inspect.Algebra.format(:infinity)
        |> IO.iodata_to_binary()
      )
    end)
  rescue
    e ->
      IO.puts(input_path)
      reraise e, __STACKTRACE__
  end

  defp reformat({:alias, meta, [thing]}, _) do
    reformat(thing, [])
    |> Enum.sort_by(fn module_path -> "#{Module.concat(module_path)}" end)
    |> Enum.map(fn alias_path -> {:alias, meta, [{:__aliases__, [], alias_path}]} end)
  end

  defp reformat({:__aliases__, _, leaf_modules}, base_modules) do
    [base_modules ++ leaf_modules]
  end

  defp reformat({{:., _, [{:__aliases__, _, more_base_modules}, :{}]}, _, children}, base_modules) do
    children
    |> Enum.flat_map(fn child_node ->
      reformat(child_node, base_modules ++ more_base_modules)
    end)
  end

  defp reformat(_, base), do: base
end
