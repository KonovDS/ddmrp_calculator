using XLSX, DataFrames, Dates, Statistics, Printf, Distributions, CategoricalArrays, Printf, CairoMakie

function plots_from_dfs(df_orders::DataFrame, df_params::DataFrame; only_sofia = false)
    # Parameters in the data:
    skus_orders, dates_orders, locs_orders = data_categories(df_orders)
    out = []
    # Parsing task:
    for row in eachrow(df_params)
        for loc in locs_orders
            # Filling the data:
            sku  = row["sku"]
            sku2 = row["sku_additional"]
            if (!(row["sku"] ∈ skus_orders) && !(row["sku_additional"] ∈ skus_orders)) || (loc != "Sofia" && !(loc ∈ locs_orders))
                continue
            end

            if only_sofia && loc != "Sofia"
                continue
            end

            # Necessary computations:
            lt  = (loc == "Sofia") ? row["lt"] : row["lt_inner"]
            moq = (loc == "Sofia") ? row["moq"] : row["moq_inner"]
            sl  = row["sl"]
            red_safety = row["red_safety"]
            oc = (loc == "Sofia") ? row["oc"] : row["oc_inner"]
            locs = (loc == "Sofia") ? locs_orders : [loc]
            
            daily = daily_filtered(df_orders, [sku, sku2], dates_orders, locs)
            sum_w = sum_over_window(daily, lt)

            μ = mean(daily)
            σ = std(sum_w)
    
            # Filling the zones:
            #(lead_time, μ, σ, order_cycle, service_level, red_safety_factor, minimum_order_quantity)
            #zones = ddmrp(lt, μ, σ, oc, sl, red_safety, moq)
            pars = lt, moq, sl, red_safety, oc
            zones = loc == "Sofia" ? ddmrp_sofia(daily, pars) : ddmrp_other(daily, pars)
            
            # Titles:
            string_title = begin
                skus = sku2 == "" ? [sku] : [sku, sku2]
                str_skus = skus[1]
                if length(skus) > 1
                    str_skus *= " ("
                    str_skus *= join(skus[2:end], ", ")
                    str_skus *= ")"
                end
                str_offices = ""
                if length(locs) == 1
                    str_offices = locs[1]
                elseif length(locs) == 7
                    str_offices = "all locations"
                elseif length(locs) > 7
                    #throw("More than 7 offices")
                    str_offices = "$(length(locs)) locations (!!!! more than 7 !!!!)"
                else
                    str_offices = "$(length(locs)) locations"
                end
                
                @sprintf("%s results for period of %d days, starting %s for %s.",
                    str_skus,
                    length(daily),
                    Dates.format(dates_orders[1], "dd u yyyy"),
                    str_offices,
                )
            end
            
            push!(out, plot2(daily, sum_w, dates_orders[1], string_title, zones[1], zones[2], (lt, sl, red_safety)))

            # Old:
            #push!(out, plot1(daily, sum_w, dates_orders[1], sku2 == "" ? [sku] : [sku, sku2], loc, lt, μ, σ, zones[1], zones[2]))
        end
    end
    out
end

#=
function plot1(daily, sum_w, date0, skus, locs, lead_time, μ, σ, red, red_p_y)
    yellow = red_p_y - red
    str_skus = skus[1]
    if length(skus) > 1
        str_skus *= " ("
        str_skus *= join(skus[2:end], ", ")
        str_skus *= ")"
    end
    str_offices = ""
    if length(locs) == 1
        str_offices = locs[1]
    elseif length(locs) == 7
        str_offices = "all locations"
    elseif length(locs) > 7
        #throw("More than 7 offices")
        str_offices = "$(length(locs)) locations (!!!! more than 7 !!!!)"
    else
        str_offices = "$(length(locs)) locations"
    end
    
    f = Makie.Figure(size = (1000, 600))
    
    # Plot 1:
    @assert size(daily) == size(sum_w)
    miny, maxy = extrema(daily)
    days_2 = size(daily, 1)
    
    # y setup:
    miny = 0
    #1o% margins:
    marginy = 0.01 * (maxy - miny)
    ticksy = ceil.(range(0, stop = ceil(maxy + marginy), length = 30))
    
    # x setup:
    # first date:
    date0 = date0 - Day(Dates.day(date0) - 1)
    dates = date0:Month(1):(date0 + Day(days_2))
    tick_dates = (Dates.value.(dates .- date0), [Dates.format(dates[1], "      u \n    yyyy"), [Dates.format(d, "      u") for d in dates[2:end]]...])
    
    ax = Makie.Axis(f[1, 1];
      limits = (-1, days_2 + 2, miny - marginy, maxy + marginy),
      xticks = tick_dates, 
      yticks = ticksy,
    )
    # Z-order
    sc1 = Makie.scatter!(ax, 1:size(daily, 1), daily; marker = :circle, color = :black, label = "daily usage", markersize = 4)
    translate!(sc1, 0, 0, -10)
    sc2 = Makie.lines!(ax, 1:size(sum_w, 1), sum_w ./ lead_time; label = "Average daily usage over LT", color = :skyblue, linewidth = 4, alpha = 0.7)

    sc3 = Makie.lines!(ax, [1, size(sum_w, 1)], [yellow/lead_time, yellow/lead_time]; label = "Yellow zone", color = :yellow, linewidth = 4, alpha = 0.7)
    translate!(sc3, 0, 0, -15)
    sc4 = Makie.lines!(ax, [1, size(sum_w, 1)], [yellow/lead_time + red/lead_time, yellow/lead_time + red/lead_time]; label = "Red zone", color = :red, linewidth = 4, alpha = 0.5)
    translate!(sc4, 0, 0, -15)
    
    # Plot 2:
    ax = Makie.Axis(f[1, 2];
      title = "",
      yticks = ticksy,
      #limits = (:auto, :auto, miny - marginy, maxy + marginy),
    )

    # Create an inset axis in the same grid cell f[1, 1]
    ax_inset = Axis(f[1, 2],
        width = Relative(0.5),    # 30% of the main plot width
        height = Relative(0.20),   # 25% of the main plot height
        halign = :right,           # Pin to right
        valign = :top,             # Pin to top
        #margin = (20, 20, 20, 20), # Add some padding from the edges
        backgroundcolor = :white, # Blocks the main plot's lines

    )
    
    # You can now plot inside it or add text
    dead_stock = red_p_y - maximum(sum_w)
    out = LaTeXString(@sprintf(
            "%s%f %s %s%f %s %s%.0f",
            L"\mu =", μ,
            "\\\\",
            L"\sigma =", σ,
            "\\\\ \\\\",
            dead_stock > 0 ? "Dead stock\$=\$" : "Shortage\$=\$",
            ceil(abs(dead_stock))
    ))
    #out = "ab\nad"
    
    text!(ax_inset, 0, 0, text = out, align = (:center, :center))
    hidespines!(ax_inset)      # Removes the box/border lines
    hidedecorations!(ax_inset) # Removes ticks and labels

    ylims!(ax, miny - marginy, maxy + marginy)
    bins = Int(floor(min(30, maxy - miny + 1)))
    translate!(
      hist!(
        ax, daily, direction = :x, # direction :x because indices are now on the X-axis of this plot
        bins = bins,
        color = :gray, alpha = 0.4, strokewidth = 0, strokecolor = :white
      ),
      0, 0, -10
    )

    ex = extrema(sum_w ./ lead_time)
    bins = Int(floor(min(10, ex[2] - ex[1] + 1)))
    h111 = hist!(
        ax, sum_w ./ lead_time,
        bins = bins,
        alpha = 0.7,
        direction = :x, # direction :x because indices are now on the X-axis of this plot
        color = :skyblue, strokewidth = 1, strokecolor = :white
    )

    # Plot 2 gaussian:
#=
    #max_count, max_idx = findmax(h111.weights)
    max_count, _ = findmax(h111[1][])

    σ1 = σ / lead_time
    dist = Normal(μ, σ1)
    x_values = range(max(0, μ - 3*σ1), stop = μ + 3*σ1, length = 100)
    y_values = pdf.(dist, x_values)

    lines!(ax, 0.4 / σ1 * lead_time * max_count * y_values, x_values)
=#
    # Legend and sizing:
    
    #sizing:
    colsize!(f.layout, 1, Relative(2/3))
    colsize!(f.layout, 2, Relative(1/3))

    f[2, 1:2] = Legend(f, [sc1, sc2, sc3, sc4], ["Daily usage", "Average daily usage over lead time \n(maximum = $(maximum(sum_w)))", "Yellow zone floor \n(expected demand = $(Int(ceil(yellow))))", "Red zone floor \n(maximal demand = $(Int(ceil(red_p_y))))"], 
                   orientation = :horizontal, 
                   tellwidth = false, 
                   tellheight = true)

    # Explaining zones:
    out = @sprintf("%s results for period of %d days, starting %s for %s.",
        str_skus,
        length(daily),
        Dates.format(dates[1], "dd u yyyy"),
        str_offices,
    )
    Label(f[0, 1:2], out, fontsize = 20) #font = :bold)

    #=
    out = LaTeXString(@sprintf(
            "%s%f, %s%f %s",
            L"\mu =", μ,
            L"\sigma =", σ,
            L"\Rightarrow \dots"
    ))
    Label(f[2, 1:2, Bottom()], out, padding = (0, 0, 0, 10))
    =#
    # Returning:
    f
end
=#

function plot2(daily, avg_daily, date0, title, red, red_plus_yellow, zone_pars; sz = (1000, 600))
    # Preliminary computations:
    lt, sl, sf = zone_pars
    yellow = red_plus_yellow - red

    # Correctness check
    @assert length(daily) == length(avg_daily)

    # Axes setup:
    f = Makie.Figure(size = sz)
    ax1 = Axis(f[1, 1], 
        ylabel = "Daily usage", 
        title = title
    )
    ax2 = Axis(f[1, 1], 
        yaxisposition = :right, 
        ylabel = "Usage over lead time", 
        #ytickcolor = :skyblue,
        #yticklabelcolor = :skyblue
    )
    hidexdecorations!(ax2)

    # Left axis ticks:
    miny, maxy = extrema(daily)
    days_2 = size(daily, 1)
    marginy = 0.01 * (maxy - miny)
    ax1.yticks = ceil.(range(0, stop = ceil(maxy + marginy), length = 30))
    date0 = date0 - Day(Dates.day(date0) - 1)
    dates = date0:Month(1):(date0 + Day(days_2))
    ax1.xticks = (Dates.value.(dates .- date0), [Dates.format(dates[1], "      u \n    yyyy"), [Dates.format(d, "      u") for d in dates[2:end]]...])
    # Right axis ticks:
    max_avg = maximum(avg_daily)
    if red != 0
        ax2.yticks = ([
            0,
            yellow,
            red_plus_yellow,
            max_avg
        ], [
            @sprintf("0"),
            @sprintf("%.0f = Y", yellow),
            @sprintf("%.0f = R+Y", red_plus_yellow),
            @sprintf("%.0f", max_avg),
        ])
    else
        ax2.yticks = ([
            0,
            red_plus_yellow,
            max_avg
        ], [
            @sprintf("0"),
            @sprintf("%.0f = R+Y", red_plus_yellow),
            @sprintf("%.0f", max_avg),
        ])
    end
    # Limits:
    ax2maxy    = maximum([max_avg, red_plus_yellow])
    ax2marginy = 0.01 * ax2maxy
    ax1.limits = (-1, days_2 + 2, miny - marginy, maxy + marginy)
    ax2.limits = (-1, days_2 + 2, 0 - ax2marginy, ax2maxy + ax2marginy)

    # Daily usage:
    scs = []
    scs_text = []
    sc1 = scatter!(ax1, 1:length(daily), daily; marker = :circle, color = :black, label = "daily usage", markersize = 6)
    push!(scs, sc1)
    push!(scs_text, "Daily usage")
    # Average daily usage over leadtime:
    sc2 = lines!(ax2, 1:length(daily), avg_daily, color = :skyblue, linewidth = 4, alpha = 0.7)
    push!(scs, sc2)
    push!(scs_text, "Usage over lead time \n \t\t\t(LT = $(lt) days)")
    # Zones:
    if red != 0
        sc3 = Makie.lines!(ax2, [1, length(daily)], [yellow, yellow]; label = "Yellow zone", color = :yellow, linewidth = 4, alpha = 0.7)
        translate!(sc3, 0, 0, -15)
        push!(scs, sc3)
        push!(scs_text, "Yellow zone floor ") #\n(expected demand = $(Int(yellow)))
    end
    sc4 = Makie.lines!(ax2, [1, length(daily)], [red_plus_yellow, red_plus_yellow]; label = "Red zone", color = :red, linewidth = 4, alpha = 0.5)
    translate!(sc4, 0, 0, -15)
    push!(scs, sc4)
    if red != 0
        push!(scs_text, "Red zone floor \n(SL = $(sl), SF = $(sf))") #\n(maximal demand = $(Int(red_plus_yellow)))
    else
        push!(scs_text, "Red zone floor") #\n(maximal demand = $(Int(red_plus_yellow)))
    end
    

    # Legend:
    sc5 = scatter!(ax1, [0], [0]; markersize = 0)
    push!(scs, sc5)
    dead_stock = Int(red_plus_yellow - max_avg)
    push!(scs_text, (dead_stock < 0 ? "Shortage = " : "Dead stock = ") * string(abs(dead_stock))) #\n(maximal demand = $(Int(red_plus_yellow)))
    f[2, 1] = Legend(f, scs, scs_text, orientation = :horizontal, tellwidth = false, tellheight = true)
    f
end

function simulator_plotter(zone_height::NTuple{3, T}, op::Vector{T}, oi::Vector{T}, misses::Union{Nothing, Vector{T}} = nothing; date0 = nothing, title = "Simulation results", size = (900, 600), text2 = "") where {T}
    if length(op) != length(oi)
        throw(ArgumentError("Incorrect sizes of op and oi"))
    end
    days = length(op)
    
    R, Y, G = zone_height
    
    # 3. Initialize the Figure and Axis
    fig = Figure(size = size)
    ax = Axis(fig[1, 1], 
        title = title,
        limits = (0, days, 0, max(G, maximum(op), maximum(oi))),
    )

    if !isnothing(date0)
        date0 = date0 - Day(Dates.day(date0) - 1)
        dates = date0:Month(1):(date0 + Day(days))
        ax.xticks = (Dates.value.(dates .- date0), [Dates.format(dates[1], "      u \n    yyyy"), [Dates.format(d, "      u") for d in dates[2:end]]...])
    end
    # 4. Add the background regions using hspan!
    if R == 0
        hspan!(ax, 0, Y, color = (:orange, 0.3))#, label = "Orange zone")
    else
        hspan!(ax, 0, R, color = (:red, 0.2))#, label = "Red zone")
        hspan!(ax, R, Y, color = (:yellow, 0.3))#, label = "Yellow zone")
    end
    hspan!(ax, Y, G, color = (:green, 0.2))#, label = "Green zone")
    
    # 5. Plot the lines
    lines!(ax, 1:days, op, color = :black, linestyle = :dash, linewidth = 2, label = "Order position (OP)")
    lines!(ax, 1:days, oi, color = :black, linewidth = 2, label = "On-hand inventory (OI)")
    if !(isnothing(misses) || sum(misses) == 0)
        lines!(ax, 1:days, misses .|> x -> x == 0 ? x - 0.1 : x, color = :red, linestyle = :dot, linewidth = 3, label = @sprintf("Unsatisfied demand (%.0f)", ceil(sum(misses))))
    end
    if (isnothing(misses) || sum(misses) == 0)
        scatter!(ax, [0], [0], markersize = 0, label = @sprintf("Dead stock = %.0f", minimum(oi)))
    end
    if text2 != ""
        scatter!(ax, [0], [0], markersize = 0, label = text2)
    end
    if R != 0
        ax.yticks = ([
            0,
            R,
            Y,
            G
        ], [
            @sprintf("0"),
            @sprintf("%.0f = R", R),
            @sprintf("%.0f = R+Y", Y),
            @sprintf("%.0f = R+Y+G", G)
        ])
    else 
        ax.yticks = ([
            0,
            Y,
            G
        ], [
            @sprintf("0"),
            @sprintf("%.0f = R+Y", Y),
            @sprintf("%.0f = R+Y+G", G)
        ])
    end
    
    # 7. Create the legend below the plot (fig[2, 1])
    Legend(fig[2, 1], ax, orientation = :horizontal, tellheight = true, nbanks = 2, tellwidth = false)
    
    # Display the figure
    fig
end