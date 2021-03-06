function [ dbCA, cones, dir, Q, P, dualized ] = eliminate( prob, destructive )
if nargin  < 2 | nargout < 8, destructive = false; end

% For the problem
%    minimize c^T * x + d
%    s.t.     y : A * x + b == 0
%             P x \in K
% The Lagrangian is
%
%               [ - d  b' 0 ]   [ 1 ]
% - [ 1, x' ] * [ - c  A' I ] * [ y ]
%                               [ z ]
%
% This function provides a smaller [ d, b' ; c, A' ] with no more nonzeros
% that solves an equivalent problem. The original x and y can be recovered
% from the reduced xx and yy by Q*[1;xx] and P*[1;-yy], respectively.

global cvx___
[ dbCA, cones, dir, Q, P ] = extract( prob, destructive );
dualized = false;
if size( dbCA, 1 ) == 1, 
    return; 
end

%
% Negate the objective so that the transformation matrices P and Q are
% properly formed.
%

dbCA(:,1) = -dbCA(:,1);
if ~issparse( dbCA ),
    dbCA = sparse( dbCA );
end

for pass = 1 : 2,

    if pass == 1 | dualized,
        n_tot = 0;
        nn  = size(dbCA,1);
        rsv = sparse( 1, 1, 1, nn, 1 );
        nng = sparse( nn, 1 );
        for k = 1 : length( cones ),
            temp = cones(k).indices;
            n_tot = n_tot + numel(temp);
            temp = sparse( temp, 1, 1, nn, 1 );
            rsv = rsv + temp;
            if isequal( cones(k).type, 'nonnegative' ),
                nng = nng + temp;
            end
        end
        n_rsv = nnz( rsv ) - 1;
        rsv   = full( rsv );
        nng   = full( nng );
        ndxs  = [ 1 : nn ]';
        nold  = nn;
    end

    % In the first pass, we don't eliminate columns which have inequality
    % structure to them, so that we can make the best decision as to
    % whether or not to convert the problem to dual standard form.
    if pass == 1,
        ineqs = rsv ~= 0;
        ineqs(1) = false;
        ineqs(ineqs) = sum( dbCA(ineqs,:) ~= 0, 2 ) == 1;
        ineqs = +full(any(dbCA(ineqs,:),1));
    elseif dualized,
        ineqs = zeros(1,size(dbCA,2));
    end
    
    while true,
        success = false;
        %
        % Look for variables which are not involved in any constraints.
        % If they appear in the objective, they are unbounded; otherwise,
        % their value does not matter and might as well be zero. Unused
        % nonnegative variables are considered here as well. If they appear
        % in the objective, they are either unbounded or zero depending
        % upon the sign of the objective coefficient.
        %
        cc   = dbCA( :, 1 );
        rcnt = sum( dbCA ~= 0, 2 );
        rows = ( rcnt == ( cc ~= 0 ) ) & ( ~rsv | nng );
        nnzr = nnz( rows );
        if nnzr > 0,
            celm = cc( rows, 1 );
            celm( nng(rows) & ( 1 - 2 * dualized ) * celm < 0 ) = 0;
            nnzc = nnz( celm );
            if ~nnzc | nnzr > 1,
                success = true;
                if nnzc,
                    cnrm = norm( celm );
                    ndxq = find( rows );
                    ndxq = ndxq( celm ~= 0 );
                    ndxq = ndxq( 1 );
                    Q( :, ndxq ) = Q( :, rows ) * ( celm / cnrm );
                    dbCA( ndxq, 1 ) = cnrm;
                    rows( ndxq ) = 0;
                end
                rowX = ~rows;
                dbCA = dbCA( rowX, : );
                rsv  = rsv ( rowX, : );
                nng  = nng ( rowX, : );
                ndxs = ndxs( rowX, : );
                Q    =    Q( :, rowX );
            end
        end
        %
        % Look for columns which differ only by a constant factor; these
        % correspond to redundant equality constraints. These occur often
        % enough, as a consequence of our transformation method, that they
        % need to be identified and eliminated.
        %
        [ xR, dbCA ] = cvx_bcompress( dbCA, 'full', 1 );
        if size( xR, 1 ) ~= size( xR, 2 ), 
            success = true;
            P = P * cvx_invert_structure( xR );
            rcnt = sum( dbCA ~= 0, 2 );
        end
        while true,
            %
            % Look for variables that we can eliminate without increasing
            % fill-in. This basically means looking for rows or columns with
            % only 1, 2, or (in some cases) 3 nonzero entries. If we
            % succeed in finding variables, we back the iterator count by
            % one so that we can try again until we fail.
            %
            [ rows, cols ] = cvx_eliminate_mex( dbCA, 1, rsv, ineqs );
            if ~any( rows ), break; end
            success = true;
            rows = rows ~= 0;
            cols = cols ~= 0;
            rowX = ~rows;
            colX = ~cols;
            %
            % [ x1^T x2^T ] [ C1 A11 A12 ] [ 1  ]
            %               [ C2 A21 A22 ] [ y1 ] = 0
            %                              [ y2 ]
            %
            % [ x1^T x2^T ] = x1^T [ I -A12*A22i ]
            %
            % [ G Y1^T Y2^T ] = [ G Y1^T ] [ I  0  -C2'*A22i'  ]
            %                              [ 0  I  -A21'*A22i' ]
            %
            A11  = dbCA( rowX, colX );
            A12  = dbCA( rowX, cols );
            A21  = dbCA( rows, colX );
            A22  = dbCA( rows, cols );
            if ( size( A22, 1 ) ~= size( A22, 2 ) | nnz( A22 ) ~= size( A22, 1 ) ),
                error( sprintf( 'There seems to be an error in the CVX presolver routine.\nPlease report this to the authors; and if possible, include the\ncvx model and data that gave you this error.' ) );
            end
            [ ii, jj, vv ] = find( A22 );
            A22i  = sparse( jj, ii, 1.0 ./ vv );
            temp  = - A22i * A21;
            P     = P( :, colX ) + P( :, cols ) * temp;
            temp  = - A12 * A22i;
            Q     = Q( :, rowX ) + Q( :, rows ) * temp';
            dbCA  = A11 + temp * A21;
            rsv   =   rsv( rowX, : );
            nng   =   nng( rowX, : );
            ndxs  =  ndxs( rowX, : );
            ineqs = ineqs( :, colX );
        end
        if ~success,
            break;
        end
    end
    
    if pass == 2 | isempty(cones),
        break;
    end
    
    %
    % Check to see if dualization will result in smaller problem
    %
    
    n_ineq   = nnz(ineqs);
    ineqs(:) = 0;
    [ rows, cols ] = cvx_eliminate_mex( dbCA, 1, rsv, ineqs );
    [n1,m1] = size(dbCA);
    m_pri  = m1 - nnz(rows) - 1;
    n_pri  = n1 - nnz(cols) - 1;
    n_pri  = n_pri + ( n_rsv ~= n_pri );
    n_eq   = m1 - 1 - n_ineq;
    m_dua  = n1 - n_ineq - 1;
    n_dua  = nnz(rsv) + n_eq + ( n_eq ~= 0 );
    if ( ( m_pri > n_pri ) | ( ( m_pri * n_pri > m_dua * n_dua ) ) & ( m_dua <= n_dua ) ), 
        ndxs = full(sparse(ndxs,1,1:n1));
        PP = cell(2,length(cones));
        n_cur = m1;
        for k = 1 : length(cones),
            temp = cones(k).indices;
            [nn,nv] = size(temp);
            temp = reshape(ndxs(temp),size(temp));
            switch cones(k).type,
                case 'semidefinite',
                    nt = 0.5*(sqrt(8*nn+1)-1);
                    SS = 'symmetric';
                case 'hermitian-semidefinite',
                    nt = sqrt(nn);
                    SS = 'hermitian';
                case 'exponential',
                    SS = sparse(inv([0,-1,0;-1,0,0;0,0,exp(1)]));
                    SS = cvx_replicate_structure(SS,nv);
                otherwise,
                    SS = [];
            end
            PP{k} = sparse(1:numel(temp),temp,1,numel(temp),n1);
            if ~isempty(SS),
                if ischar(SS),
                    SS = cvx_create_structure([nt,nt,nv],SS);
                    SS = SS * SS';
                end
                PP{k} = SS * PP{k};
            end
            cones(k).indices = reshape(n_cur+1:n_cur+nn*nv,nn,nv);
            n_cur = cones(k).indices(end);
        end
        dbCA  = vertcat(dbCA',PP{:});
        dir   = -dir;
        tmp   = Q; Q = P; P = tmp;
        nold  = size(dbCA,1);
        Q(:,nold) = 0;
        dualized = true;
    end
    
end

%
% Return the objective back to normal.
%

if dualized,
    P = -P;
    P(:,1) = -P(:,1);
else
    dbCA(:,1) = -dbCA(:,1);
end

%
% Move the cone indices to their new locations
%

ndxs = full( sparse( ndxs, 1, 1 : length( ndxs ), nold, 1 ) );
tt = zeros(1,length(cones));
for k = 1 : length( cones ),
    temp = ndxs(cones(k).indices);
    if all(temp),
        temp = reshape( temp, size(cones(k).indices) );
    else
        temp = nonzeros(temp);
        temp = reshape( temp, 1, length(temp) );
    end
    tt(k) = isempty(temp);
    cones(k).indices = temp;
end
if any(tt),
    cones(tt~=0) = [];
end

% Copyright 2008 Michael C. Grant and Stephen P. Boyd.
% See the file COPYING.txt for full copyright information.
% The command 'cvx_where' will show where this file is located.
