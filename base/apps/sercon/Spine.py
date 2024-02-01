def IndexTerminals(terms):
    indices = []     # terms[_indices_] -> [ tname tname .. ]
    types = []       # terms[_types_] -> [ 'motor' 'sensor' .. ]
    tiles = {}       # terms[_tiles_] -> { tile# : [indices] }
    joints = {}      # terms[_joints_] -> { jointname : termindex }
    for tname in sorted(terms.keys()):
        if tname.startswith("_"):
            raise Exception("Illegal term key: "+tname)
        term = terms[tname]
        index = len(indices)
        term['_index_'] = index
        j = term.get('joint')
        if j:
            joints[j] = index
        opttile = term.get('tile')
        if not opttile == None:
            if opttile not in tiles:
                tiles[opttile] = []
            tiles[opttile].append(index)
            indices.append(tname)
            types.append(term.get('type'))
    terms['_indices_'] = indices
    terms['_tiles_'] = tiles
    terms['_joints_'] = joints
    terms['_types_'] = types
    print("INDSL",indices,types)
    

